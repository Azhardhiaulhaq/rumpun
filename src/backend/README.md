# Rumpun backend

FastAPI modular monolith for Rumpun's first backend slice. PostgreSQL is the production system of record; SQLite is used only by the deterministic test suite.

## Features

- Email/password registration and login with Argon2id password hashes
- Google ID-token sign-in behind an injectable verifier
- Signed short-lived access tokens and hashed, rotating, revocable refresh sessions
- Household tenant context and membership-scoped reads
- Posting-derived dashboard balances
- Candidate inbox, detail, optimistic edits, review state transitions, and idempotent confirmation
- Balanced double-entry postings, database-backed idempotency, audit events, and structured metadata-only request logging
- SQLAlchemy 2.x models and an Alembic initial migration

## Local setup

Python 3.12 and PostgreSQL 16 or newer are expected.

```bash
cp .env.example .env
# Replace RUMPUN_JWT_SECRET and adjust the database URL.
python -m venv .venv
. .venv/bin/activate
pip install -e '.[dev]'
alembic upgrade head
uvicorn app.main:app --reload
```

OpenAPI UI is at `http://localhost:8000/api/v1/docs`. The schema is at `/api/v1/openapi.json`.

Docker Compose provides PostgreSQL and the API:

```bash
cp .env.example .env
docker compose up --build
```

If another local service already holds port 8000, pick a different one:

```sh
RUMPUN_API_PORT=8010 docker compose up --build
```

The compose credentials are local development placeholders and must not be used for deployment.

## Validation

```bash
ruff format --check .
ruff check .
mypy app
pytest
```

To check the migration with SQLite's supported subset:

```bash
RUMPUN_DATABASE_URL=sqlite:///migration-check.db alembic upgrade head
RUMPUN_DATABASE_URL=sqlite:///migration-check.db alembic check
```

PostgreSQL should be used for deployment migration validation because its enum and concurrency behavior are authoritative.

## API endpoints

All application endpoints use `/api/v1`.

- `GET /health`
- `POST /auth/register`
- `POST /auth/login`
- `POST /auth/google`
- `GET /onboarding/invites`
- `POST /onboarding/household`
- `POST /onboarding/invites/{id}/accept`
- `POST /onboarding/invites/{id}/decline`
- `GET /accounts`
- `POST /accounts`
- `GET /transactions`
- `POST /transactions`
- `POST /transfers`
- `GET /inbox/address`
- `POST /inbox/address`
- `POST /inbox/address/rotate`
- `POST /inbound/email`
- `GET /household`
- `PATCH /household`
- `GET /household/people`
- `POST /household/invites`
- `DELETE /household/invites/{id}`
- `POST /auth/refresh`
- `POST /auth/logout`
- `GET /dashboard`
- `GET /candidates`
- `GET /candidates/{candidate_id}`
- `PATCH /candidates/{candidate_id}`
- `POST /candidates/{candidate_id}/confirm`
- `POST /candidates/{candidate_id}/reject`
- `POST /candidates/{candidate_id}/duplicate`

Authenticated routes accept `Authorization: Bearer <access-token>`. `X-Household-ID` selects an active household, and membership is verified in the same query. If omitted, the earliest membership is selected. Confirmation requires `Idempotency-Key`.

## Security and operational limits

## Recording money

Every transaction is double entry: two postings that sum to zero.
An expense moves value out of an account and into household equity; income does the reverse; a transfer moves it between two accounts and leaves the total untouched.
Balances are therefore always derivable from the postings, and no screen has to trust a stored total.

Amounts are unsigned integers in the currency's smallest unit, and `transaction_type` carries the direction.
A signed amount plus a type would let a client negate the value twice, so the API returns the magnitude everywhere.

`POST /transactions` and `POST /transfers` require an `Idempotency-Key`.
A phone on a weak connection retries, and a retry must not post the money a second time.
The same key with a different body is a `409`: replaying the first result would silently swallow the second payment.

Owners, admins, and members can record money.
Viewers and children can read the ledger but never write to it.

## Transaction email

Rumpun does not read anyone's mailbox.
Reading Gmail needs a restricted OAuth scope, Google app verification, and for production a third-party security assessment, which is a heavy price for a family ledger.
Instead each household gets an unguessable forwarding address, and the household forwards the mail it wants Rumpun to see.
The trade is a one-time manual setup in Gmail against no third-party review and a much smaller blast radius.

The address is a secret in the same sense a webhook URL is: anyone holding it can create candidates, so it is generated with `secrets.token_hex` and can be rotated without touching anything else.
Mail to an unknown or retired address is accepted and dropped rather than refused, because a distinct error would confirm which addresses exist.

`POST /inbound/email` is called by the mail provider, not by the app, so it is authenticated with an HMAC-SHA256 signature over the raw body in `X-Rumpun-Signature` and compared in constant time.
Without `RUMPUN_INBOUND_WEBHOOK_SECRET` the endpoint returns `503` rather than running unauthenticated.

Gmail mails a confirmation code to a new forwarding address before it will send anything there.
Rumpun receives that mail, recognises it, stores the code, and shows it in the app, so nobody has to go hunting for it.

Nothing that arrives by email reaches the ledger on its own.
A message becomes a `transaction_candidate` that a person confirms, and the parser leaves a field empty rather than guessing: a missing amount stops the candidate at `needs_input`, while a confident wrong amount would post a wrong number.

Signing in never creates a household. A first-time user has no household and no membership until they either create one through `POST /onboarding/household` or accept an invitation. Auto-creating one would strand an invited family member in an empty ledger of their own, which is why the two steps are separate.

Invitations are matched on the normalized email Google verified at sign-in, so accepting one proves the invitee controls the address that was invited. A partial unique index allows only one pending invitation per address per household; resolved rows stay for the audit trail. An invitation addressed to someone else answers `404`, not `403`, so a wrong guess does not confirm that it exists. Only an owner or admin can invite or revoke, and a second owner cannot be invited.

Google sign-in verifies ID tokens with `google-auth`, configured audience, and accepted Google issuers. It is disabled unless `RUMPUN_GOOGLE_CLIENT_ID` is set. Tests replace only the verifier dependency; no provider token is stored or returned.

Refresh tokens are random opaque values. Only SHA-256 digests are stored. Rotation detects replay and revokes the token family. Access JWTs are short-lived and contain no private or financial data.

The included rate limiter is process-local. It is suitable only as a development and single-process abuse-control seam. Production must enforce shared limits at a gateway or Redis-backed service.

Logs contain request ID, method, route path, status, duration, and lifecycle events. Request bodies, headers, query strings, email content, token values, descriptions, and amounts are intentionally excluded.

Candidate confirmation uses database uniqueness for both the candidate-to-ledger link and `(household_id, operation, idempotency key)`. PostgreSQL transaction isolation and uniqueness are the production concurrency boundary. The application creates one negative account posting and one positive household-equity posting in the same currency, then commits the candidate state, transaction, postings, audit event, and idempotency result atomically.

This slice does not include email sync, Gmail mailbox OAuth, invitations, manual financial creation, restricted-account grants, budgets, assets, or corrections. It implements the requested registration, sign-in, dashboard, and candidate review surface only.
