# Location sharing on iPhone: implementation plan

Status: plan only; nothing in this document is implemented yet.
It extends `location-sharing-plan.md`, whose product decisions still apply unless stated otherwise here.

## Goal

Let Lita start, extend, and stop sharing from her iPhone with the same consent rules as Android.
Azhar receives the same "started sharing" and "arrived" notifications he would get from an Android sharer.
The iPhone already receives notifications from Azhar's sharing, so this plan only covers the sharing side.

## What already exists and carries over

The server contract is platform-neutral.
Sessions, area snapshots, the session-scoped tracking token, position uploads, stop, extend, and arrival deduplication all work unchanged.

Arrival detection now runs on the server from uploaded positions (`app/location_arrivals.py`).
The iPhone therefore only has to upload positions reliably while sharing.
It does not need its own detector to deliver arrival alerts, which removes the hardest iOS-specific risk.

The Dart detector in `lib/location/arrival_detector.dart` uses the same rules as the server.
It stays available if offline arrival confirmation on iPhone is wanted later, but it is not required for the first iOS release.

The Flutter UI (`lib/location/location_screen.dart`) talks to native code over the `rumpun/location` method channel.
Its methods are `device`, `start`, `extend`, `stop`, `status`, `interrupted`, and `clear`.
The iPhone implements the same channel, so the Flutter screen only needs its Android-only guard removed.

## The iOS constraint that shapes the design

iOS has no foreground service.
An app keeps receiving location in the background only when all of these hold:

- The app declares the `location` background mode in `UIBackgroundModes`.
- The `CLLocationManager` sets `allowsBackgroundLocationUpdates = true` while sharing.
- Updates were started while the app was in the foreground, from an explicit user action.
- The user has granted at least "While Using the App" permission.

With "While Using" permission and background updates enabled, iOS shows the blue location indicator in the status bar while sharing.
That indicator plays the role of Android's persistent notification: a visible, system-owned sign that sharing is on, which the user can tap to return to the app.
"Always" permission is not needed for this model and must not be requested.
Asking for it would add a second system prompt, an App Store review justification, and a permanent capability the product does not use.

If the user force-quits the app from the app switcher, iOS stops delivering location.
Server expiry and the two-minute stale-position cutoff already bound what the household sees in that case.
The next app launch must reconcile and stop the interrupted session, exactly like Android, and never resume it silently.

## Native implementation

Add `ios/Runner/LocationSharing.swift`, registered from `AppDelegate` on the implicit engine's messenger under `rumpun/location`.

### Permission and start

1. Flutter checks location services and precise accuracy with `geolocator`, as it does on Android.
   On iOS, precise accuracy maps to `CLAccuracyAuthorization.fullAccuracy`.
   If the user granted approximate location, show the existing "Lokasi presisi diperlukan" message and stay idle.
2. Flutter shows the existing consent dialog, then creates the server session.
3. `start` receives session ID, tracking token, base URL, device ID, and remaining milliseconds.
4. Native code configures one `CLLocationManager`:
   - `desiredAccuracy = kCLLocationAccuracyBest`
   - `distanceFilter = 10`
   - `activityType = .otherNavigation`
   - `pausesLocationUpdatesAutomatically = false`, because automatic pausing would end updates during a long dwell
   - `allowsBackgroundLocationUpdates = true`
   - `showsBackgroundLocationIndicator = true`
5. Call `startUpdatingLocation()` and store a local deadline based on `ProcessInfo.systemUptime`, which keeps counting even if the user changes the device clock.
6. Persist only the session ID as an "interrupted" marker in `UserDefaults`.
   Store the tracking token in the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, never in `UserDefaults`.

If any step after session creation fails, Flutter stops the server session, as it already does on Android.

### While sharing

- Keep only the newest unsent position, matching the Android service.
- Upload every 10 seconds while moving (speed above 1 m/s) and every 30 seconds while stationary, using a `URLSession` default configuration.
  A background `URLSession` is unnecessary because the app stays running while location updates continue.
- Wrap each upload in `beginBackgroundTask` so a request started just before suspension can finish.
- Treat HTTP 401, 403, and 409 from position upload as "sharing has ended" and tear down.
- Check the deadline on every location callback and on a 15-second timer; stop at expiry without a network call.

### Stop and teardown

`stop`, expiry, permission loss (`locationManagerDidChangeAuthorization`), and location services being switched off all run the same teardown:

1. `stopUpdatingLocation()` and set `allowsBackgroundLocationUpdates = false`.
2. Clear the queued position and the Keychain token.
3. Fire `POST /sessions/{id}/stop` once; if it fails, keep only the interrupted marker so the next launch reconciles it.

There is no notification Stop action on iOS.
Stop is available on the Lokasi screen, and the blue status-bar indicator brings the user back to it.
Optionally, a later phase can add a Live Activity with a Stop button on the Lock Screen and Dynamic Island.
That needs a widget extension and is out of scope for the first iOS release.

### Extend

`extend` replaces the deadline and the tracking token in place.
It must not restart location updates or change the area snapshot.

## Info.plist and project changes

- Add `location` to `UIBackgroundModes`, alongside the existing `fetch` and `remote-notification`.
- Replace `NSLocationWhenInUseUsageDescription` with text that covers sharing, for example:
  "Rumpun memakai lokasimu untuk menampilkan posisimu di peta dan, saat kamu mulai berbagi, membagikannya ke anggota rumah sampai waktu berbagi habis."
- Do not add `NSLocationAlwaysAndWhenInUseUsageDescription`.
- Add `NSLocationTemporaryUsageDescriptionDictionary` with a `SharingArrival` purpose key, used by `requestTemporaryFullAccuracyAuthorization` when the user granted approximate location.
  This gives a one-tap way to grant precise location for the session instead of only showing an error.

## Flutter changes

- Replace the Android-only `_nativeSharingAvailable` guard with Android or iOS.
- Change the "Berbagi lokasi saat ini tersedia di Android." copy, since it would no longer be true.
- On iOS, explain the blue status-bar indicator in the start dialog in place of the Android persistent notification.
- Keep the iOS-specific permission wording in one place so Android copy is unchanged.

## Server changes

None are required for basic sharing.
Two small improvements are worth making with this work:

- Record `platform` on the session (from the existing push device platform or a new start field) for diagnostics only.
- Log, without coordinates, how many positions a session received, so that "no alert arrived" can be told apart from "no positions arrived".
  This is the question that took production database inspection to answer in October 2026.

## Testing

Automated:

- Swift unit tests for deadline handling, upload cadence selection, and teardown on each end condition.
- Existing backend arrival tests already cover detection from uploaded positions.

On a real iPhone (Lita's iPhone 12 or a test device), with explicitly started test sessions only:

- Start sharing, lock the phone, and confirm positions keep arriving on the server for at least 15 minutes.
- Switch to other apps, including navigation and camera, and confirm uploads continue.
- Low Power Mode on: confirm uploads continue, and record the observed cadence honestly.
- Turn off location services, revoke permission in Settings, and grant only approximate location; each must stop sharing and must not resume.
- Force-quit from the app switcher, then reopen: the app must show the session as ended and stop it on the server.
- Expiry while offline: sharing must stop locally at the deadline.
- Walk or drive from outside a saved area into it and stay for at least 30 seconds; Azhar's Android phone must receive "Tiba di …" once.
- Extend during a session: no second start notification, arrival state preserved.

Simulator location simulation can exercise the arrival path, but it does not prove background behavior, so a device run is required before calling this delivered.

## App Store review notes

Background location with "While Using" permission is allowed for user-initiated, time-limited sharing that the user can see and stop.
The review notes must explain that sharing starts only from an explicit action, has a fixed end time, and shows the system indicator throughout.
Do not describe the feature as tracking or monitoring other people.

## Order of work

1. Native channel with `device`, `status`, `interrupted`, `clear`, and `stop`, plus the Flutter guard change behind a debug flag.
2. Start, upload, deadline, and teardown with Keychain token storage.
3. Info.plist background mode, permission copy, and temporary full-accuracy flow.
4. Device testing per the list above, with Lita's consent for any session on her phone.
5. Remove the debug flag and ship.
6. Optional later: Live Activity with a Stop button, and on-device arrival confirmation for offline periods.
