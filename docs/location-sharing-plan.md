# Rumpun location-sharing implementation plan

Status: product decisions agreed through interview; implementation has not started.
This document describes planned behavior and validation, not shipped functionality.

## Goal

Let a household member explicitly share their live location for a limited time so other members can coordinate travel and meeting points.
Notify the other members when sharing starts and when the sharing member arrives inside a saved household area.
Tracking remains off unless the member starts it themselves.

## Scope

Implement Android sharing, viewing, area editing, and notifications first.
Keep the backend contracts and client domain logic platform-neutral so native iPhone support can be added later.
Do not implement an iPhone tracking service, web viewer, or browser notifications in this phase.
The user's wife uses an iPhone, so this Android-first phase does not yet deliver the full couple-to-couple workflow.

Existing finance data, OAuth credentials, deployment, and household naming remain unchanged.
Use isolated location fixtures and explicitly started test sessions rather than changing production financial records.

## Agreed product decisions

### Consent and session lifecycle

- Tracking is off by default.
- A member can start, extend, and stop only their own session; owners and admins cannot activate someone else's tracking.
- Require internet and server acknowledgement before location collection for sharing begins.
- Require precise location permission to start.
- Offer 30 minutes, 1 hour, 2 hours, and 4 hours, with 1 hour selected by default.
- Show the end time before starting.
- Allow one active session per member.
- Tapping sharing while a session is active opens remaining time, Extend, and Stop controls.
- Extension preserves the session's area snapshot and already-notified areas.
- Sharing continues while the app is backgrounded or the screen is locked.
- Android shows a persistent sharing notification with a Stop action.
- Stop, expiry, reboot, revoked location permission, or disabled location services end sharing.
- Never restart tracking automatically after reboot, permission restoration, or location-services restoration.
- Stopping or expiry does not send a separate push notification.
- Extending does not send another start notification.

### Saved household areas

- Every household member can create, edit, and delete shared areas.
- Areas belong to the household, not only their creator.
- Use an embedded OpenStreetMap-based map with manual pan and zoom.
- Place search and address geocoding are not required.
- Draw polygons by tapping corners, with Undo, movable corners, and a name before saving.
- Require at least three distinct corners and reject self-intersecting or degenerate polygons.
- A Lokasi saya action may obtain a one-time local position to centre the editor, but must not start sharing or upload that position.
- Each session takes an immutable snapshot of every saved area at its start.
- Later additions, edits, and deletions affect future sessions only.
- Explain this snapshot behavior in the editor and active-session details.

### Arrival rules

- Any area in the session snapshot can trigger an arrival alert.
- Each area can notify once per session.
- Establish starting-area membership using the first reliable position.
- Do not notify just because the first reliable position is inside an area.
- After a reliably observed outside-to-inside transition, require 30 seconds of reliably detected presence inside.
- Poor accuracy or uncertain boundary position pauses arrival confirmation.
- Combine arrivals confirmed close together, including overlapping areas, into one notification.
- Mark every area included in a combined event as notified for that session.

### Live updates and offline behavior

- Target updates approximately every 10–15 seconds while moving and 30–60 seconds while stationary.
- These are targets, not guarantees of Android scheduling, GPS availability, or connectivity.
- Show last-update age and position uncertainty instead of implying perfect real-time accuracy.
- Hide coordinates after two minutes without an update, even if the session remains unexpired.
- Continue local arrival detection during temporary connection loss in an established session.
- On reconnection during that active session, send queued arrivals with actual arrival time and delayed labeling.
- At Stop or expiry, discard all unsent arrival alerts and location uploads.
- An offline Stop halts local collection immediately; reconcile the stop with the server after reconnection.
- An interrupted session must not automatically resume on app startup.

### Data and notification privacy

- Store only the latest position for an active session, never a route history.
- Replace previous coordinates rather than appending location samples.
- Hide coordinates immediately when the server knows a session has ended.
- Delete stored coordinates at session end.
- Server expiry remains authoritative even when the sharing phone is offline or stopped unexpectedly.
- Other household members receive sharing-start and arrival notifications; exclude the sharing member.
- Each recipient has independent Sharing started and Arrival alerts preferences, enabled by default.
- Muting affects only that recipient's notifications, not tracking or map access.
- Explain notification-permission denial without pretending pushes are available.

## Existing codebase integration points

The Flutter frontend lives in `src/frontend`.
Its authenticated requests and session handling are in `lib/api/auth_repository.dart` and `lib/api/api_client.dart`.
`lib/household_home.dart` currently contains the informational location placeholder and the finance shell.
`lib/push_notifications.dart` handles FCM registration and notification-open events for finance kinds.
`lib/main.dart` owns routes, session restoration, and foreground notification presentation.

The current Android manifest is `android/app/src/main/AndroidManifest.xml`.
It declares notification permission but no location permission or location foreground service.
Background sharing therefore needs explicit native lifecycle implementation, not just a Flutter timer or a screen-owned position subscription.

The Python backend lives in `src/backend`.
It already has household membership authorization, SQLAlchemy models, Alembic migrations, and tests.
`app/push.py` queues and dispatches FCM events through `NotificationOutbox` and registered `PushDevice` records.
`app/push_worker.py` runs delivery work.
The current notification retry policy can retain events for days, which is unsuitable for location events unless session validity and cancellation are added.

Reuse authentication, household scoping, device registration, and notification delivery foundations.
Do not couple location payloads to financial candidates or route every location notification into Tinjau.

## Architecture

### Domain boundaries

Introduce dedicated modules for saved areas, sharing sessions, live positions, arrival detection, and location notification preferences.
Keep polygon evaluation and the session state machine independent of Flutter widgets and native Android APIs.
Define a platform tracking interface for start, stop, permission status, service status, and position events.
Android implements this interface first; iOS can later implement the same contract with its own lifecycle and permission behavior.

The foreground service owns tracking and local expiry, not the map screen.
The map viewer owns presentation and polling only; viewing another member never starts the viewer's tracking.
The server owns authorization, session deadlines, area snapshots, deduplication, visibility, and notification dispatch.

### Proposed backend resources

Names below are proposed contracts to finalise during implementation, not existing endpoints.

| Resource | Responsibility |
|---|---|
| Household location areas | Shared named polygons with versioned edits |
| Location session | Owner, household, start/end time, state, and immutable area snapshot |
| Latest position | Single replaceable coordinate with accuracy, observation time, and update sequence |
| Arrival event | Idempotent area arrivals with actual arrival time and delayed status |
| Location preferences | Recipient-specific start and arrival notification choices |

Suggested routes under `/api/v1/location`:

- `GET /areas`, `POST /areas`, `PATCH /areas/{id}`, and `DELETE /areas/{id}`.
- `GET /sessions` for household-visible active sessions and freshness status.
- `POST /sessions` to start the authenticated user's session.
- `GET /sessions/current` to reconcile the current user's session.
- `POST /sessions/{id}/extend` and `POST /sessions/{id}/stop`.
- `PUT /sessions/{id}/position` to replace the latest position.
- `POST /sessions/{id}/arrivals` for idempotent confirmed arrivals.
- `GET /preferences` and `PATCH /preferences` for the current recipient.

Use replay-safe request keys for start, extend, stop, and arrivals.
Enforce one active session per user with database-level concurrency protection.
Reject updates from non-owners, expired sessions, stopped sessions, obsolete session identifiers, or removed household members.
Use server-issued session identity and deadlines; never trust client-supplied household ownership or arbitrary extension times.

### Session states

Client states: idle, checking requirements, starting, active, active with degraded connectivity or accuracy, stopping, and ended with a reason.
Only start the sharing service after a successful server response and a final permission/lifecycle check.
If service startup fails after session creation, stop the server session and explain the failure.

Keep the native expiry deadline available without Flutter UI or network access.
Use a monotonic clock for elapsed local tracking deadlines and dwell durations where available.
Server UTC time controls authorization and display expiry.
Reconcile device-clock differences rather than allowing clock changes to prolong sharing.

Unexpected process/service interruption must not silently restart a prior session.
Persist a minimal reconciliation marker, without a movement history, so opening the app can terminate an interrupted server session and offer an explicit new start.
Do not register a boot receiver that resumes tracking.

An offline stop or abrupt reboot cannot instantly inform the server.
The two-minute stale-position cutoff and hard session expiry bound visibility in that case.
Present this limitation honestly rather than promising immediate remote deletion without connectivity.

### Arrival detection

Implement a deterministic detector with per-area starting, outside, candidate-inside, and notified states.
Starting inside suppresses the initial alert but does not prohibit a later genuine outside-to-inside arrival in the same session.

Use position accuracy when evaluating polygon membership.
A centre point alone inside a polygon is insufficient when its uncertainty overlaps the boundary.
Require a confidently outside position to arm an entry and confidently inside observations to confirm it.
Choose and document accuracy thresholds after fixture and real-device testing.

Do not accumulate 30 seconds across unrelated inside observations separated by long gaps or uncertain GPS.
A proposed conservative approach resets the dwell candidate on uncertainty or a reliable exit and confirms only with sufficiently fresh inside observations spanning 30 seconds.
Sample more frequently near boundaries or during dwell confirmation than the stationary upload interval.
Acquisition cadence and upload cadence are separate concerns.

Use a short, bounded aggregation window for nearby confirmed arrivals; five seconds is an initial engineering proposal, not an additional agreed product promise.
Preserve each area's actual confirmation time.
Use unique session-and-area keys so retries and overlapping delivery never notify twice.
The server should validate area identity, timestamps, session validity, and plausibility without retaining the underlying route.
Define the client trust boundary explicitly: arrival messages are informational coordination, not proof of presence or a security guarantee.

### Offline queues

Keep only the newest unsent position, not a series of coordinate samples.
A bounded local arrival queue contains session identity, area identity, confirmation time, and replay key, without a travelled route.
Check session validity immediately before uploading or queueing notification work.
Clear queued location and arrival data on stop, expiry, sign-out, permission loss, or interruption.
A durable stop-reconciliation marker is allowed because it ends tracking rather than records whereabouts.

Cancel pending start/arrival outbox entries when a session ends.
Re-check session validity, recipient membership, and notification preferences immediately before FCM dispatch, including retries.
Messages already accepted by FCM cannot be recalled reliably; document this transport limitation and use a short session-aware TTL.
Avoid coordinates in push payloads or notification bodies.
Notification taps open the relevant location session or an honest ended-session view.

### Coordinate deletion and retention

Reads must filter expired and stale positions immediately, independent of periodic cleanup.
Run server cleanup for expired sessions and physical coordinate deletion even if no client reconnects.
Stop transactions remove the latest position and cancel pending session alerts.
Keep only minimal operational metadata for deduplication and diagnostics, with an explicit retention period selected before implementation is shipped.
Exclude coordinates, polygon payloads, and sensitive request bodies from application logs, analytics, crash breadcrumbs, and notification payloads.
Address database backups and point-in-time recovery separately: deleting a live row does not instantly erase historical backups.
Do not promise backup erasure until deployment retention is verified.

## Android implementation

Start a location foreground service from an explicit, visible user action.
Declare only the location and foreground-service permissions required by the selected implementation and supported Android versions.
Do not assume background-location permission is necessary merely because the screen can be locked; verify the user-started location foreground-service model against current platform requirements before adding it.

The persistent service notification shows sharing status, end time, and a functioning Stop action.
Use a dedicated channel separate from recipient arrival/start alert channels.
Permission prompts occur at the relevant action, not at app launch.
If approximate permission is granted, explain why this version needs precise location and remain idle.

Monitor location-services state, permission loss, service termination, authentication loss, and expiry.
Stop location acquisition before attempting remote cleanup.
Avoid indefinite wakelocks, decorative background work, or automatic reboot resumption.
Test Samsung power management, Doze, locked-screen behavior, and interruption rather than claiming delivery from an emulator-only test.

## Embedded map and provider selection

Use open-map data with visible attribution and a replaceable tile-provider configuration.
A Flutter map renderer such as `flutter_map` is a candidate, subject to dependency and license review.
OpenStreetMap data being open does not mean public tile hosting is unrestricted or unlimited.
Select a provider only after checking its current usage terms, attribution, request limits, caching rules, and cost expectations.
Do not call a free tier permanently free or use public OSM infrastructure contrary to its policy.

Map browsing sends tile requests to a third-party provider, potentially revealing the viewed area and network address.
Document that privacy boundary and avoid claiming the map is entirely local.
Do not add geocoding, reverse geocoding, or search services in this phase.

## UI and antislop direction

Apply antislop during implementation.
Use the current white, sage, slate, and restrained apricot system, with ENERGY 2 / RHYTHM 2 / MOTION 2.
Keep the branch identity and functional map controls; do not add invented avatars, fake routes, example locations presented as real, or tracking-like decoration.

Replace Beranda's coming-soon location card with a real location summary once the feature is available.
Provide a real Lokasi destination only when its screen and routes work.
Keep the shared app shell consistent rather than embedding an unrelated module framework.

### Location overview

- Embedded map showing fresh active household positions and relevant saved areas.
- Member identity, update age, and accuracy indication.
- Clear no-one-sharing, map-loading, tile-error, API-error, and stale-session states.
- A Mulai berbagi action when idle.
- Remaining time, Extend, and Stop when sharing.
- Saved-area management and recipient notification preferences.

### Area editor

- Name, tap-to-place corners, visible boundary, Undo, movable vertices, and save validation.
- An alternative accessible vertex-editing control, not a drag-only workflow.
- Cancel discards an unsaved draft without modifying the shared area.
- Explain that changes apply to future sessions.
- Use a local one-time positioning action only after explicit permission.

### Start and active controls

Show duration, exact end time, household audience, and what arrival alerts do before starting.
Do not imply another member must grant permission to view an explicitly shared household session.
Show that notification permission and location permission serve different purposes.
Keep Stop reachable from the app and persistent Android notification.
Use short transitions for sheets, editor mode, and changing session controls, respecting reduced motion.
Avoid continuous decorative marker pulses or a live-looking pin when updates are stale.

## Implementation stages

### 1. Contracts and safety foundation

Record the baseline commit and current automated results.
Choose map and Android location dependencies after checking current platform requirements and provider terms.
Define schemas, session states, extension semantics, retention, accuracy thresholds, and aggregation timing.
Finalise polygon size/vertex limits and coordinate-validation policy.
Use conservative bounds appropriate to meeting areas rather than claiming global polygon support without geodesic handling.

### 2. Backend resources

Add reviewed migrations, household-scoped areas, immutable snapshots, sessions, latest-position replacement, preferences, and idempotent arrivals.
Add expiry cleanup and session-aware outbox cancellation.
Implement concurrency and authorization tests before connecting production location collection.

### 3. Platform-neutral domain logic

Build polygon validation, accuracy-aware membership, initial-area suppression, dwell confirmation, aggregation, and per-area deduplication with deterministic clocks and fixtures.
Build session reconciliation and bounded offline queues.
Keep this code independent of screens and Android service glue.

### 4. Android service and consent flow

Implement permission checks, user-started foreground service, persistent notification Stop, local deadline, and teardown paths.
Test collection disabled before acknowledgement and after every end condition.
Prove the lifecycle with a safe explicitly started device session before relying on it for arrivals.

### 5. Map UI and household viewing

Implement map, area editor, sharing controls, freshness/accuracy states, and Beranda entry.
Connect existing auth and household APIs without altering finance flows.
Handle notification deep links across cold start, restored session, and ended sessions.

### 6. Arrival notifications

Integrate local confirmation, offline delayed events, server replay protection, combined notifications, recipient preferences, and session-aware FCM delivery.
Use a second Android device or a controlled recipient fixture for delivery validation.
The connected Samsung alone cannot prove real member-to-member push delivery.

### 7. End-to-end and delivery

Run automated checks and direct Samsung tests.
Inspect UI states, safe areas, text scaling, touch targets, keyboard accessibility, map attribution, and runtime logs.
Resolve layout, lint, test, and lifecycle issues before delivery.
Write an evidence-backed antislop report separating real-device checks, fake-location fixtures, backend integration, source inspection, and anything not exercised.

## Acceptance tests

### Backend

- Cross-household reads, writes, area edits, and notification access are denied.
- Only the owner can update, extend, or stop their session.
- Concurrent starts create at most one active session.
- Expired/stopped sessions reject positions and arrivals.
- Out-of-order positions cannot replace a newer observation.
- Snapshot boundaries and names remain unchanged during a session.
- Duplicate arrivals and request retries do not duplicate alerts.
- Preferences and membership are rechecked at delivery.
- Stop and expiry cancel undelivered session notifications.
- Stale and expired coordinates are unavailable from reads.
- Cleanup deletes coordinates without requiring client reconnection.

### Detector and client fixtures

- Starting inside does not notify.
- Leaving a starting area and returning reliably can notify once.
- Presence shorter than 30 seconds does not notify.
- Drift, boundary ambiguity, long sample gaps, and poor accuracy do not fabricate dwell.
- Overlapping confirmed arrivals combine correctly.
- Extension preserves snapshot and already-notified state.
- Offline arrivals deliver only after reconnecting during an active session.
- Stop/expiry discard arrivals and unsent positions.
- Viewing, map editing, and session restoration do not start live sharing.
- Reduced motion, large text, narrow layouts, loading, empty, and recoverable error states work.

### Samsung and second-device checks

- Explicit start with real permission flow and visible end time.
- Location collection remains off when start is rejected or cancelled.
- Sharing updates while screen locked and during app switches.
- Persistent notification Stop ends collection without opening the app.
- Timer expiry works offline and with Flutter UI absent.
- Internet loss shows stale status, hides the pin after two minutes, and reconciles correctly.
- Permission revocation, location-services disablement, service interruption, and reboot do not resume tracking.
- Mock-location fixtures exercise boundary entry and combined arrival behavior without claiming a real journey.
- Real start and arrival pushes reach a controlled second Android recipient when available.
- Notification taps open the intended map/session and handle already-ended sessions honestly.
- Area creation, vertex correction, edit, cancellation, and deletion work without changing an active snapshot.
- No financial records are changed for these checks.

## Details to finalise in engineering planning

The following are not additional user-approved guarantees.
Resolve them through implementation review and tests, escalating only material product changes.

- Tile provider, renderer, Android service/location dependency, and supported Android version matrix.
- Accuracy confidence threshold, observation freshness, and boundary hysteresis parameters.
- Aggregation window for combined arrivals.
- Extension increment and maximum end-time policy, retaining the agreed finite durations and explicit consent.
- Polygon complexity, area-size limits, overlap display, and optimistic edit-conflict handling.
- Minimal session/event metadata retention and backup-deletion disclosure.
- Behavior on multiple signed-in devices, with a device-bound tracking session to prevent duplicate collectors.
- Foreground-service startup rollback and unexpected process-interruption reconciliation.
- Polling cadence for viewers and server rate limits, without silently adding route storage.

## Deferred

Native iPhone sharing, iPhone notification verification, web viewing, address search, indefinite sharing, movement history, remote tracking activation, automatic reboot resumption, and arrival security guarantees are outside this phase.
Do not present any of them as implemented.
