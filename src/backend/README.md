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

Google sign-in verifies ID tokens with `google-auth`, configured audience, and accepted Google issuers. It is disabled unless `RUMPUN_GOOGLE_CLIENT_ID` is set. Tests replace only the verifier dependency; no provider token is stored or returned.

Refresh tokens are random opaque values. Only SHA-256 digests are stored. Rotation detects replay and revokes the token family. Access JWTs are short-lived and contain no private or financial data.

The included rate limiter is process-local. It is suitable only as a development and single-process abuse-control seam. Production must enforce shared limits at a gateway or Redis-backed service.

Logs contain request ID, method, route path, status, duration, and lifecycle events. Request bodies, headers, query strings, email content, token values, descriptions, and amounts are intentionally excluded.

Candidate confirmation uses database uniqueness for both the candidate-to-ledger link and `(household_id, operation, idempotency key)`. PostgreSQL transaction isolation and uniqueness are the production concurrency boundary. The application creates one negative account posting and one positive household-equity posting in the same currency, then commits the candidate state, transaction, postings, audit event, and idempotency result atomically.

This slice does not include email sync, Gmail mailbox OAuth, invitations, manual financial creation, restricted-account grants, budgets, assets, or corrections. It implements the requested registration, sign-in, dashboard, and candidate review surface only.
