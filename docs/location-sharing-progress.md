# Location sharing build progress

Status: backend deployed; map and native tracking prototype implemented; feature is not ready for delivery.
The agreed source of scope remains `location-sharing-plan.md`.
Antislop applies during development; no location UI has been added yet.

## Implemented foundations

- Household-scoped area create/read/edit/delete endpoints with versioned editing.
- Polygon limits and validation for duplicate corners, crossing edges, bounds, and degenerate areas.
- Explicit session start with finite presets, one active session per user, device identity, and immutable area snapshot.
- Replay handling for session start and owner-only stop.
- Single replaceable position, sequence/time validation, and device-bound uploads.
- Position hiding after two minutes without updates and removal on stop/expiry.
- An expiry cleanup worker entry point, not yet configured in deployment.
- Alembic migration for area and session tables, not applied to production.
- Platform-neutral Dart arrival detector with initial-inside suppression, reliable entry, thirty-second dwell, accuracy-aware boundaries, and per-area deduplication.
- Detector resets dwell on uncertain readings or observation gaps longer than twenty seconds.

## Checks

Backend suite: 127 tests passed.
Frontend suite: 101 tests passed.
Flutter analysis: no issues.
Targeted backend Ruff checks: passed.
Diff whitespace check: passed.

These checks validate foundations, not the entire location feature.
The API now queues sharing-start events, accepts deduplicated combined arrivals, supports replay-safe extensions and current-session reconciliation, and stores recipient preferences.
Delivery rechecks session validity and preferences; stop/expiry cancel pending events, and location FCM messages use a short TTL.
The Flutter location repository now exposes areas, sessions, and notification preferences through the existing authenticated request pipeline.
These additions are not yet connected to a map or native tracking service.
Device ID is a client binding, not hardware attestation.

## Remaining

- Broader notification delivery tests, local arrival aggregation, Android notification channels, and native location notification routing.
- Broader cross-household, multi-device, concurrency, migration, and retention tests.
- Configure and verify periodic expiry cleanup and operational metadata retention.
- Map-provider decision, map UI, polygon editor, and location destination.
- Native Android foreground service, consent prompts, notification Stop, expiry, offline queues, and interrupted-session reconciliation.
- Integrate the deterministic detector with native sampling and upload cadence.
- Native notification routing and household viewer freshness states.
- Safe E2E validation, direct Samsung lifecycle testing, and complete antislop delivery evidence.

The Samsung was reconnected by USB for the second implementation session.
Its installed package was inspected, but no new location UI or tracking service exists to exercise on the phone yet.
Production migrations `b6a21f4d9c03` and `c9d312efab04` were applied after a verified database backup on the server.
The deployed API health check passed and the location cleanup worker is running.
Backup: `/home/azhar/rumpun/backups/location-before.dump`, restricted to the deployment user.
An embedded OSM map and basic polygon creation screen were installed and opened on the Samsung without starting sharing.
Android location and foreground-service permissions are declared but no real session was started during these checks.
The native foreground service and accuracy-aware arrival detector compile in the latest release build.
No financial write was performed.

## Remaining acceptance blockers after deployment

- Area edit/delete, selected-vertex repositioning, one-time centring, preferences UI, and extension UI are now implemented and compile; direct device acceptance remains pending.
- Reconcile interrupted sessions, Stop failures, sign-out, and multiple devices safely.
- Ordinary 15-minute access tokens were replaced in the native service with session-scoped JWT credentials, accepted only for that session's position, arrival, and stop endpoints.
- Extension refreshes the scoped credential; ordinary authenticated endpoints reject location credentials.
- Session-scoped credential changes were deployed; API health and worker status passed.
- Native work now uses one drain task, a replaceable latest position, bounded per-area arrival events, Stop-time connection cancellation, and monotonic expiry checks.
- Verify network cancellation races and offline service behavior on device.
- Confirm background acquisition and adaptive upload cadence on the Samsung.
- Complete combined-arrival aggregation and timestamp presentation.
- Location notification navigation and session identity/freshness/accuracy labels are implemented.
- Map provider policy/attribution review and real delivery validation remain pending.
- A local own-location marker with accuracy circle and 400 ms position interpolation is implemented.
- Its foreground subscription is cancelled when the page is disposed, and it never uploads by itself.
- Reduced motion skips interpolation.
- Latest analysis and all 101 frontend tests passed; release APK built successfully, but ADB still listed no device so this build was not installed.
- Direct foreground-service and locked-screen tests with explicitly started test sessions.
- Samsung disconnected from ADB during the latest pass; no device was listed on repeated checks.
- Latest release APK builds successfully, and analysis plus 101 frontend/127 backend tests passed before the latest viewer-label refinement.
- A second controlled recipient for actual push delivery.
- Full antislop delivery gate; do not claim the prototype is finished.

## Arrival alert fix (October 2026)

Production showed 4 real sessions and 448 position uploads, but zero arrival reports from the phone, so no arrival notification was ever queued.
The Android detector required the whole GPS uncertainty circle to fit inside the area, rejected readings worse than 50 m, and restarted the 30-second dwell on any uncertain reading or 20-second gap.
Indoor readings in a 66 by 47 m area almost never satisfied that.

The server now confirms arrivals from uploaded positions (`app/location_arrivals.py`), so existing installs benefit without an app update.
Readings up to 100 m accuracy count; a centre inside the polygon counts as inside; uncertain readings pause the dwell instead of restarting it; silences up to 3 minutes are tolerated.
The Android and Dart detectors now use the same rules, and per-session area uniqueness prevents duplicate alerts from both paths.
Start notices now show local time (`pukul 18.26`) instead of an ISO timestamp.
A replay of a walk into the real `apartment` area against a restored production copy queued and dispatched `Tiba di apartment.` to the other member.
Migration `e5a7c3d1b820` was applied after a backup at `/home/azhar/rumpun/backups/before-lists-202610101754.dump`.
The cleanup worker no longer crashes when PostgreSQL restarts.

A real walk-in on device with both phones is still pending.
iPhone sharing is planned in `location-sharing-ios-plan.md`.
