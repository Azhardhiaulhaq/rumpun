# Rumpun Flutter prototype

A phone-first Flutter client for the initial Rumpun flow:

- splash that resumes a stored session
- Google sign-in, the only way into the app
- onboarding: create a household, or accept an invitation waiting for your email
- the ledger: real balances, recording money, and moving it between accounts
- the review inbox for proposed transactions from Gmail or forwarded email
- member roster with email invitations and withdrawal
- home with balance privacy control and transaction actions
- transaction review with editable confirmation and rejection
- explicit ready, loading, empty, and error states on data screens

Authentication and membership are real: `/auth/google`, `/auth/refresh`, `/auth/logout`, `/onboarding/*`, and `/household/*` are called over HTTP, and the refresh token is kept in the platform keychain. There is no email or password form; Google carries the identity. The home and review screens still show demo financial figures, which are marked as such on screen.

## Configure

Copy `.env.example` to `.env` and fill it in. The file is gitignored.

```sh
cd src/frontend
cp .env.example .env
```

| Key | Notes |
| --- | --- |
| `RUMPUN_GOOGLE_CLIENT_ID` | The **Web** client ID from Google Cloud Console. The backend verifies the ID token's `aud` against it, so the Android and iOS client IDs do not work here. |
| `RUMPUN_API_BASE_URL` | Where the app looks for the API, including the `/api/v1` prefix. `http://10.0.2.2:8000/api/v1` reaches the host from an Android emulator; a physical phone needs a LAN address or a tunnel. |

Recording money requires an `Idempotency-Key`, generated once per sheet rather than per attempt, so a retry on a weak connection cannot post the same amount twice.

The one-tap Gmail connection lives under Profil, then Hubungkan Gmail.
The backend setup and Google verification requirements are in `docs/gmail-connect-setup.md`.
The older forwarding endpoint is documented in `docs/email-forwarding-setup.md`.

Signing in does not create a household. A first-time user lands on onboarding and either starts one or accepts an invitation sent to their email, so an invited family member joins the existing ledger instead of an empty one of their own.

`RUMPUN_GOOGLE_CLIENT_ID` is not optional. Google sign-in is the only entry point, so a build without it shows an explanatory message where the button would be, rather than a dead control.

These are **compile-time** values. Editing `.env` has no effect until the next build; hot reload will not pick it up.

## Run against a local backend

Start the API first:

```sh
cd src/backend
docker compose up -d
```

Then run the app:

```sh
cd src/frontend
flutter run --dart-define-from-file=.env
```

The same flag works for `flutter build` and `flutter test`. If `.env` is missing, Flutter stops with `Did not find the file passed to "--dart-define-from-file"` rather than building an app that cannot sign in.

A single value can still be overridden on the command line, which wins over the file:

```sh
flutter run --dart-define-from-file=.env \
  --dart-define=RUMPUN_API_BASE_URL=http://192.168.1.10:8000/api/v1
```

VS Code users get this automatically: `.vscode/launch.json` passes the flag for both run and profile configurations.

Google sign-in additionally needs the running build's signing certificate registered in Google Cloud Console. For a debug build that is the debug keystore SHA-1:

```sh
keytool -list -v -keystore ~/.android/debug.keystore \
  -alias androiddebugkey -storepass android -keypass android
```

Each machine has its own debug keystore, so every developer adds their own SHA-1 to the same Android OAuth client. A missing fingerprint surfaces as `ApiException: 10` with no further detail.

## Prototype controls

On the home and review screens, the three-dot menu switches between data, loading, empty, and error states. This is only a review aid for the screens that are not yet backed by the API.

## Checks

```sh
cd src/frontend
flutter analyze
flutter test
```

`test/` runs offline against a mocked HTTP client and needs no configuration. The contract tests in `test_live/` talk to a real backend and are excluded from the default run:

```sh
cd src/backend && docker compose up -d
cd ../frontend && flutter test test_live --tags live
```

Point them at a tunnel to check what a phone will actually reach:

```sh
flutter test test_live --tags live --dart-define-from-file=.env
```
