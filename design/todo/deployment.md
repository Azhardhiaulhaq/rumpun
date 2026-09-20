# Before this runs anywhere but a laptop

Each of these is fine for local development and not fine in production.
None is blocked on anything; they just have not been done.

## Secrets

**`docker-compose.yml:20` hardcodes the JWT secret** as `local-compose-secret-change-before-deploying`, and a value set in compose beats the one in `.env`.
That bit once already: the inbound webhook silently kept using a test secret because it had been passed on the command line.
Anyone with this value can mint access tokens for any account.

**The inbound webhook secret** in `src/backend/.env` is real, but was generated for local testing and has been echoed into a terminal more than once.
Rotate it when the Worker is deployed, and change it in both places at the same time or mail stops arriving.

**The database password** in compose is `local-only-password`.

## Android

**Release builds are signed with the debug key** (`android/app/build.gradle.kts:27`).
A debug-signed APK cannot be updated by a properly signed one later without uninstalling, so this has to be fixed before the first real install, not after.

Generate an upload keystore, keep it out of the repository, and load it from a properties file or the CI secret store.

## Operational

**ngrok's URL changes on restart**, and when it does the Cloudflare Worker keeps posting to a dead hostname.
Mail fails silently.
A Cloudflare Tunnel with a fixed hostname removes the problem.

**`RUMPUN_API_PORT` is not sticky.**
Running `docker compose up` without it moves the API back to 8000, which has already caused a confusing half hour when ngrok pointed at 8010.
Put the value in `.env` rather than typing it each time.

**Rate limiting is 10 attempts per 60 seconds** and was raised to 500 for contract-test runs.
Confirm production uses the real value.

## Google

**No iOS OAuth client exists yet**, so sign-in will not work on an iPhone.
The Android and Web clients are registered; only the Web client ID is in config, because the backend verifies `aud` and an Android client ID would fail with `invalid_google_audience`.

**Sign in with Apple is required** by App Store review for any app offering Google sign-in.
Not started.

## Data

**A confirmed candidate keeps its parsed email body**, and `RUMPUN_INBOUND_RETAIN_BODY_DAYS` defaults to 30 but nothing enforces it yet.
There is no job that deletes anything.

**No backup.**
The Postgres volume is local and has never been dumped.
