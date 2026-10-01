# Connect Gmail in Rumpun

Rumpun signs users in with Google and asks for Gmail permission separately.
Each Gmail grant belongs to one Rumpun user and one household.
The Flutter screen opens Google's consent page, and Google returns to the Python backend at `/api/v1/gmail/oauth/callback`.
No Gmail token is sent to Flutter.

## Google Cloud

Create a Web application OAuth client for the public Rumpun app.
Keep the existing Google sign-in client for login.
Add the exact backend callback URL as an authorized redirect URI, for example `https://api.example.com/api/v1/gmail/oauth/callback`.
The backend must be reachable over HTTPS for a deployed app.
Local development can use a localhost redirect URI registered on the same Web client.
An Android emulator cannot reach the host machine through its own `localhost` browser address, so device testing needs an HTTPS backend URL or tunnel.

Declare `openid`, `email`, and `https://www.googleapis.com/auth/gmail.readonly` on the consent screen.
Set the audience to External when people outside the Workspace organization should connect.
Google classifies `gmail.readonly` as restricted, so public distribution requires restricted-scope verification.
Because Rumpun processes this data on a server and will transmit relevant content to Jev, plan for Google's security assessment and the Google API Services User Data Policy.
Do not describe the app as approved until Google completes its review.

## Backend configuration

Set these values in the backend's secret manager or deployment environment:

```sh
RUMPUN_GMAIL_OAUTH_CLIENT_ID=<Web OAuth client ID>
RUMPUN_GMAIL_OAUTH_CLIENT_SECRET=<Web OAuth client secret>
RUMPUN_GMAIL_OAUTH_REDIRECT_URI=https://api.example.com/api/v1/gmail/oauth/callback
RUMPUN_GMAIL_TOKEN_KEY=<Fernet key>
RUMPUN_GMAIL_SYNC_MINUTES=30
RUMPUN_JEV_API_KEY=<add after Jev is ready>
```

Generate the encryption key once with `python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())'`.
Keep it stable and backed up; changing or losing it makes stored Gmail refresh tokens unreadable.
Never put client secrets, refresh tokens, or the Fernet key in Flutter or Git.
The old desktop `gmail-oauth.json` file is not used by this flow and is ignored by Git.
Run Uvicorn with `--no-access-log` so callback authorization codes are not written to access logs; the API still emits structured logs without query strings.

Run `alembic upgrade head` before enabling the feature.
Schedule `python -m app.gmail_sync` every few minutes in the backend environment.
The local Docker Compose file runs the same command every five minutes in its `gmail-worker` service.
The command checks each active Gmail connection when 30 minutes have passed since its last sync, then classifies up to 200 queued messages per connection when `RUMPUN_JEV_API_KEY` is set.
Schedule the command as a single worker to avoid concurrent processing of the same connection.

## Data flow

1. A signed-in user taps **Hubungkan Gmail**.
2. FastAPI creates a short-lived, single-use OAuth state and a PKCE verifier.
3. Google redirects to FastAPI after the user grants read-only Gmail access.
4. FastAPI checks the Google identity against the Rumpun user and encrypts the refresh token in PostgreSQL.
5. The sync job reads Gmail history and records new message IDs without fetching bodies.
6. After Jev is configured, the job fetches each pending message, asks Jev whether it confirms a transaction, and creates a candidate for likely or uncertain transactions.
7. A person reviews and confirms each candidate before it changes the ledger.

The first connection starts from the current Gmail history ID, so it processes new mail rather than importing the old mailbox.
If Gmail history expires, the job scans the mailbox for missing message IDs.
Disconnecting deletes the local grant and queued message IDs and asks Google to revoke the refresh token.

Google documentation: [Gmail scopes](https://developers.google.com/workspace/gmail/api/auth/scopes), [Web server OAuth](https://developers.google.com/identity/protocols/oauth2/web-server), and [restricted-scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification).
