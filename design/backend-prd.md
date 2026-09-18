# Rumpun Backend Product Requirements Document

**Status:** Draft v0.1  
**Product name:** Rumpun  
**Initial market:** Family finance for a household  
**Initial clients:** Flutter mobile app for Android and iOS  
**Primary backend:** Python/FastAPI with PostgreSQL

## 1. Executive summary

Rumpun is a family application whose first module helps household members track financial accounts, assets, budgets, and expenses. A user creates or joins a household, records financial activity, and optionally connects Gmail. The backend identifies relevant transaction emails and creates reviewable transaction candidates. Nothing imported from email changes the financial ledger until a permitted household member confirms it.

The backend must be suitable for an initial two-person household while establishing the tenant isolation, authorization, auditability, data integrity, and integration boundaries needed for an eventual public product.

## 2. Product principles

1. **The household is the tenant.** Every household-owned resource must be scoped by `household_id`.
2. **Email creates suggestions, not facts.** Imported messages create candidates; users confirm them before ledger posting.
3. **The ledger is append-only.** Posted financial entries are corrected with reversals or adjustment transactions, not destructive edits.
4. **Balances are derived.** The system derives balances from postings and never treats a mutable balance column as the source of truth.
5. **Least data necessary.** Gmail synchronization fetches only messages matching the configured query/label, even though the OAuth scope may technically permit broader access.
6. **Every retry is safe.** Mobile requests, Gmail notifications, synchronization jobs, and parser jobs must be idempotent.
7. **Explain automation.** Every candidate records its source, parser version, confidence, and extracted evidence.
8. **Privacy defaults matter.** Raw email retention is limited, secrets are encrypted, and financial details are hidden from logs and push-notification previews by default.

## 3. Goals

### 3.1 MVP goals

- Register and authenticate users.
- Create a household and invite another adult.
- Support household roles and resource-level permissions.
- Create cash, bank, e-wallet, budget-envelope, investment, foreign-currency, and physical-asset accounts.
- Record expenses, income, transfers, and adjustments through an auditable ledger.
- Define monthly category budgets and report progress.
- Record assets and append-only valuations.
- Connect Gmail using OAuth 2.0.
- Restrict application processing to configured Gmail labels or search queries.
- Synchronize matching email and parse known transaction templates.
- Deduplicate email messages and transaction candidates.
- Present imported transactions for review, edit, confirmation, or rejection.
- Import the existing TandemBot ledger with preserved provenance and legacy IDs.
- Expose a versioned API suitable for Flutter.
- Record security-relevant activity in an audit log.

### 3.2 Public-readiness goals

- Strong household tenant isolation.
- Account deletion, Gmail disconnection, token revocation, and data export workflows.
- Google OAuth verification readiness.
- Horizontal worker scaling without duplicate ledger postings.
- Pluggable email providers so Microsoft Graph can be added later.
- Parser versioning and replay without corrupting confirmed transactions.
- Operational observability without logging private financial/email content.

## 4. Non-goals for MVP

- Direct bank-account aggregation or open-banking integration.
- Automatic posting of email-derived transactions without human confirmation.
- Money movement, bill payment, or card issuance.
- Tax, accounting, or regulated financial advice.
- Stock trading or brokerage execution.
- Full investment cost-basis and capital-gains accounting.
- Full mailbox search as a general-purpose email client.
- Reading Gmail from the Flutter app in the background.
- Supporting arbitrary IMAP credentials for public users.
- AI agent autonomy over the financial ledger.

## 5. Users and roles

### 5.1 User

An authenticated person with an independent identity. One user may eventually belong to multiple households.

### 5.2 Household roles

| Role | Capabilities |
|---|---|
| `owner` | Full household administration, billing, deletion, ownership transfer, integrations, and finance access |
| `admin` | Manage members, accounts, categories, budgets, integrations, and transactions, except owner-only operations |
| `member` | View permitted household finance data; create and review transactions according to account access |
| `viewer` | Read-only access to permitted resources |
| `child` | Restricted access configured by an adult; not part of the first UI release |

The database and authorization layer must support these roles from the start, although the first mobile release may expose only `owner`, `admin`, and `member`.

### 5.3 Resource visibility

Accounts have a visibility mode:

- `household`: visible to all adult household members.
- `restricted`: visible only to explicitly granted household members.

All transactions involving a restricted account inherit restrictive visibility. Authorization must be enforced in backend queries, not only in Flutter.

## 6. Key user journeys

### 6.1 Create a household

1. User authenticates.
2. User creates a household with name, timezone, locale, and base currency.
3. Backend creates owner membership and default categories.
4. User receives an active household context.

### 6.2 Invite a spouse

1. Owner/admin creates an invitation with a role.
2. Backend sends or returns a time-limited invitation link.
3. Recipient authenticates and accepts.
4. Backend creates membership and marks invitation accepted.
5. Audit events record both actions.

### 6.3 Add an expense manually

1. Member submits expense details with an idempotency key.
2. Backend validates access, accounts, currency, and amount.
3. Backend creates a transaction and balanced ledger postings atomically.
4. Response includes the posted transaction and affected account balances.

### 6.4 Connect Gmail

1. Flutter requests a Gmail authorization URL from the backend.
2. Backend creates signed OAuth state tied to the current user and household.
3. User consents on Google.
4. Google redirects to the backend callback.
5. Backend exchanges the authorization code server-side.
6. Backend encrypts the refresh token and stores scope/grant metadata.
7. User configures a Gmail label or query, defaulting to `label:RumpunFinance`.
8. Backend validates the query and starts initial synchronization.
9. Flutter displays connection and synchronization status.

### 6.5 Review an email-derived transaction

1. Worker discovers a matching Gmail message.
2. Backend stores message metadata and optionally encrypted normalized body.
3. Parser extracts transaction fields and records evidence/confidence.
4. Deduplication links likely duplicate sources/candidates.
5. Flutter shows the candidate in a review inbox.
6. User edits and confirms, rejects, or marks it duplicate.
7. Confirmation atomically creates the posted ledger transaction and links it to the candidate.

### 6.6 Correct a posted transaction

1. User selects a posted transaction.
2. User submits a correction.
3. Backend creates a reversal transaction and a replacement transaction in one database transaction.
4. Original records remain available in history.

## 7. Functional requirements

### 7.1 Authentication and sessions

- Support email verification and at least one production authentication method.
- Recommended initial methods: email/password or magic link plus Google/Apple sign-in later.
- Access tokens should be short-lived; refresh tokens must be revocable and rotated.
- Record sessions/devices and permit remote revocation.
- Require recent authentication for destructive or highly sensitive operations.
- Rate-limit login, token refresh, invitation, export, and OAuth initiation endpoints.

### 7.2 Household tenancy and authorization

- Every household resource carries `household_id`, directly or through an immutable parent.
- Every request resolves an authenticated user and active household membership.
- Never accept authorization based only on an object ID supplied by the client.
- Object fetches must include household and visibility predicates.
- A user may not assign a role equal to or higher than their allowed administrative level.
- Last-owner removal is forbidden until ownership is transferred or the household is deleted.

### 7.3 Financial accounts

Supported kinds:

- `cash`
- `bank`
- `ewallet`
- `credit_card`
- `budget_envelope`
- `investment`
- `foreign_currency`
- `physical_asset`
- `loan`
- `other`

Account requirements:

- Name, kind, currency, owner/member association, visibility, status.
- Optional institution and masked identifier.
- Account archive instead of destructive deletion after ledger use.
- Opening balances represented by an opening-balance transaction.
- Account balance derived from posted ledger entries.

### 7.4 Transactions and ledger

Supported business transaction types:

- `expense`
- `income`
- `transfer`
- `adjustment`
- `opening_balance`
- `refund`
- `reversal`

Requirements:

- Store money as signed integer atomic units using currency exponent metadata. For IDR, one stored unit is one rupiah.
- A transaction contains two or more postings whose signed amounts balance per currency.
- Cross-currency transfers require explicit source amount, destination amount, and optional fees; each currency leg must be represented explicitly.
- Transaction status: `draft`, `posted`, `reversed`, or `void` (only unused drafts may be voided).
- Posted transactions cannot be deleted.
- Corrections create reversal/replacement records.
- Every write supports an `Idempotency-Key`.
- Receipts and source messages may be linked without becoming ledger truth.

### 7.5 Categories and budgets

- Household-defined hierarchical categories.
- Category types at minimum: expense and income.
- Monthly budget periods in the household timezone.
- Initial budget model: category limit with optional rollover.
- Budget scopes: household or selected member.
- Progress is calculated from posted transaction allocations.
- Transfers do not consume expense budgets by default.
- Budget overspend is allowed but surfaced.

### 7.6 Assets and valuations

- Asset accounts may represent gold, property, vehicles, investments, foreign currency, or other holdings.
- Valuations are append-only observations with value, currency, effective date, and source.
- Quantity may be recorded using exact decimal values and an explicit unit.
- Net-worth reporting uses latest eligible valuation and liabilities.
- Historical valuation records are not overwritten.

### 7.7 Gmail integration

#### Authorization

- Use Google OAuth 2.0 authorization-code flow with PKCE where applicable.
- Authorization code exchange occurs in the backend.
- Store refresh tokens encrypted with key version metadata.
- Never send Gmail refresh tokens to Flutter.
- Record granted scopes exactly.
- Handle token revocation, consent removal, and reauthorization.

#### Scope behavior

- Reading transaction-email bodies normally requires a Gmail scope capable of message-content access, such as read-only Gmail access.
- Gmail OAuth authorization cannot generally be restricted by Google to one label or sender.
- Rumpun must enforce a product-level boundary: it only lists and fetches messages matching the user-configured label/query.
- The consent UI and privacy policy must explain both the technical scope and the narrower application behavior accurately.

#### Synchronization

MVP may use scheduled polling. Production may use Gmail mailbox watches and Google Cloud Pub/Sub.

- Default query: `label:RumpunFinance`.
- User may choose a validated query from supported filters.
- Initial sync has a configurable lookback, default 30 days and maximum 365 days.
- Persist Gmail message ID, thread ID, history ID/checkpoint, internal date, and content hash.
- Enforce a unique key per connection and provider message ID.
- Fetch only matched messages.
- Recover from expired Gmail watches and invalid history checkpoints with a bounded resync.
- Do not interpret removal of an email as deletion of a confirmed financial transaction.

#### Data minimization

- Prefer extracting text/plain or sanitized text from the relevant MIME parts.
- Do not load remote images or tracking pixels.
- Reject or quarantine unexpectedly large messages/attachments.
- Raw email body retention is configurable; recommended default is 30 days after successful extraction.
- Keep minimal immutable provenance—provider message ID/hash, sender domain, received time, parser version, and extraction evidence—after raw body expiry.
- Users can delete unconfirmed source data and disconnect/revoke the integration.

### 7.8 Parsing

- Parsers implement a versioned interface.
- Known institutions use deterministic template parsers first.
- Parser output includes matched institution/template, amount, currency, transaction time, merchant/counterparty, masked account identifier, reference, confidence, and evidence spans.
- Unrecognized emails create no financial transaction automatically.
- An optional LLM fallback may be introduced only with explicit privacy disclosure, redaction, strict structured output validation, and mandatory human review.
- Parser replay creates a new parsing attempt and never silently changes a previously confirmed ledger transaction.

### 7.9 Deduplication

Deduplication operates at two levels:

1. **Message-level:** unique `(email_connection_id, provider_message_id)` and content hash.
2. **Transaction-level:** candidate comparison using household, account, amount, currency, merchant/reference, and a configurable time window.

Possible duplicate candidates are grouped and presented to users. The system must not silently discard a candidate solely because a heuristic score is high.

### 7.10 Candidate review

Candidate states:

- `pending`
- `needs_input`
- `confirmed`
- `rejected`
- `duplicate`
- `expired`

Requirements:

- Show extracted values, source, confidence, warnings, and duplicate matches.
- A reviewer can amend proposed fields before confirmation.
- Confirmation checks authorization and account visibility.
- Confirmation is atomic and idempotent.
- Only one ledger transaction may be created from a candidate.
- Rejection does not delete source provenance immediately.

### 7.11 Receipts and attachments

- Store files in private S3-compatible object storage.
- Persist metadata in PostgreSQL.
- Use short-lived signed download URLs after authorization.
- Virus scan or quarantine uploads before availability.
- Enforce content-type and size limits.
- Never expose a permanent public object URL.

### 7.12 Notifications

- Push notifications notify users that review items exist.
- Financial amount/merchant must be hidden from lock-screen text by default.
- Notification delivery failure does not affect candidate state.
- Users can configure digest versus per-candidate notifications.

### 7.13 Existing TandemBot migration

- Import accounts, transactions, valuations, and receipt references from `/home/azhar/.openclaw/workspace/finances.json` through a one-time migration tool.
- Preserve original transaction IDs in `external_legacy_id`.
- Preserve legacy flags and ledger start date as migration metadata.
- Convert current opening balances into auditable opening-balance entries.
- Convert each business transaction into balanced postings.
- Preserve source JSON read-only as a checksum-addressed migration artifact.
- Produce a reconciliation report comparing every imported account balance and valuation with the old ledger.
- Require explicit sign-off before the new backend becomes source of truth.

## 8. API requirements

- Base path: `/api/v1`.
- JSON request/response except file upload/download and OAuth browser redirects.
- UUIDv7 or UUID identifiers generated server-side.
- RFC 3339 timestamps in UTC; household timezone is used for reporting boundaries.
- Cursor-based pagination for changing collections.
- Stable machine-readable error codes.
- `Idempotency-Key` required for financial posting, candidate confirmation, invitations, and other retried mutations.
- Optimistic concurrency through a version field or `If-Match` for editable resources.
- OpenAPI specification generated from FastAPI and treated as a tested contract.

The detailed contract is in [`api-contract.md`](./api-contract.md).

## 9. Non-functional requirements

### 9.1 Security

- TLS for all network traffic.
- Encryption at rest for database volumes and object storage.
- Application-layer envelope encryption for Gmail refresh tokens and optionally retained raw bodies.
- Password hashing with Argon2id if passwords are supported.
- Secrets kept outside source control.
- OWASP ASVS-inspired controls for authentication, authorization, input validation, session management, and logging.
- Dependency and container-image scanning in CI.
- No sensitive values in logs, traces, analytics, crash reports, or push payloads.
- CSRF/state protection on OAuth callbacks.
- SSRF-safe handling of links and MIME content; do not retrieve arbitrary email-linked URLs.
- Audit events for authentication, membership, exports, integration changes, and ledger posting/reversal.

### 9.2 Privacy and compliance readiness

- Publish a privacy policy and data-deletion procedure before external users.
- Maintain a data inventory and retention schedule.
- Provide household export and deletion workflows.
- Revoke provider tokens upon disconnect/deletion when possible.
- Prepare for Google OAuth app verification and any security assessment applicable to the selected Gmail scopes and deployment architecture.
- Do not claim that Gmail access is technically label-restricted if the granted scope can read broader mailbox content.

### 9.3 Reliability

Initial objectives:

- API availability target: 99.5% monthly for MVP, increasing before paid launch.
- No acknowledged financial write may be lost.
- Database point-in-time recovery and daily encrypted off-site backups.
- Restore procedure tested at least quarterly.
- Jobs use leases/retries and dead-letter handling.
- Exactly-once effects are achieved through uniqueness and idempotency, not assumptions about message delivery.

### 9.4 Performance

- p95 API read latency below 400 ms under expected MVP load, excluding external providers.
- p95 ordinary write latency below 700 ms.
- Candidate confirmation below 1 second under normal conditions.
- New matching Gmail email should normally become a candidate within 5 minutes for polling MVP and 1 minute after push-based integration.

### 9.5 Observability

- Structured logs with request/job correlation IDs.
- Metrics for API latency, status codes, Gmail sync lag, token failures, parser match rates, job retries, duplicate rates, and candidate confirmation rates.
- Distributed tracing across API and workers where useful.
- Alert on sustained Gmail failures, queue backlog, backup failure, and reconciliation invariant violations.
- Never attach raw email bodies, tokens, notes, or unmasked identifiers to telemetry.

## 10. Proposed architecture

```text
Flutter Android/iOS
        |
        | HTTPS JSON + OAuth browser handoff
        v
FastAPI application
  |-- Authentication/session service
  |-- Household authorization service
  |-- Finance/ledger service
  |-- Budget and asset service
  |-- Gmail connection service
  |-- Review service
  |-- Audit service
        |
        +--> PostgreSQL (system of record)
        +--> S3-compatible private storage (receipts/temporary raw MIME)
        +--> Redis/queue (jobs, not financial source of truth)
        +--> Background workers
                  |-- Gmail synchronization
                  |-- MIME normalization
                  |-- Parsing
                  |-- Deduplication
                  |-- Notifications
        +--> Google OAuth/Gmail API
        +--> FCM/APNs
```

A modular monolith is recommended initially. Service boundaries should exist in code, but separate network services would add unnecessary operational complexity at MVP scale.

## 11. Suggested Python components

- FastAPI
- Pydantic v2
- SQLAlchemy 2.x
- Alembic
- PostgreSQL 16+
- `httpx` and Google auth/API libraries
- A durable worker framework selected during implementation (for example, Dramatiq/Celery/Arq), with PostgreSQL idempotency guards regardless of queue choice
- Redis if required by the chosen worker
- S3-compatible storage
- Pytest, Hypothesis for ledger invariants, Ruff, mypy/pyright

## 12. Success metrics

### Product

- At least 90% of known supported-bank emails produce a candidate with correct amount and currency.
- At least 80% of supported candidates require no field edits before confirmation.
- Duplicate-posting rate is zero; suspected duplicate-candidate rate is measured separately.
- Median review time below 30 seconds per candidate.
- Household members can reconcile account balances with their source accounts.

### Engineering

- 100% of posted transactions satisfy ledger balancing invariants.
- 100% of financial create requests pass idempotency tests.
- Cross-household authorization tests cover every household resource route.
- Backup restoration and TandemBot migration reconciliation complete successfully before cutover.

## 13. MVP phases

### Phase 0 — Foundation

- Repository, CI, configuration, local Docker environment.
- Authentication, households, memberships, categories.
- Database schema and migration framework.
- Audit and idempotency infrastructure.

### Phase 1 — Financial ledger

- Accounts, transactions, postings, derived balances.
- Manual expense/income/transfer entry.
- Reversals and corrections.
- Initial budgets, assets, and valuations.

### Phase 2 — Gmail review pipeline

- Google OAuth connection.
- Label/query configuration.
- Poll-based synchronization.
- Source-message normalization.
- Initial parsers and candidate review API.
- Deduplication and notification.

### Phase 3 — Flutter integration and private alpha

- Household onboarding and invitation.
- Manual transactions and dashboard.
- Gmail connection status.
- Review inbox and confirmation.
- Import/reconcile TandemBot data.

### Phase 4 — Public hardening

- Google OAuth verification readiness.
- Push-based Gmail watch/Pub/Sub.
- Data export/deletion and consent records.
- Abuse controls, operational dashboards, restore test, penetration testing.
- App-store privacy declarations and production policies.

## 14. Acceptance criteria for first private release

- Azhar can create a household and invite Lita.
- Both can sign in independently and see permitted shared accounts.
- Both can create an expense manually without duplicate posting on request retry.
- Transfers preserve balanced ledger invariants.
- At least one Gmail account can connect and synchronize only messages matching the configured application query.
- A supported test transaction email creates exactly one pending candidate.
- Confirming that candidate creates exactly one posted transaction.
- Repeating Gmail delivery, parser execution, or confirmation creates no duplicate posting.
- Raw email and Gmail credentials are absent from application logs.
- Existing TandemBot balances reconcile after test migration.
- Disconnecting Gmail prevents future synchronization and revokes or deletes stored credentials.

## 15. Open product decisions

The following require owner decisions before implementation is finalized:

1. Authentication provider and login methods.
2. Whether private/restricted accounts are required in MVP.
3. Exact household roles exposed in the first release.
4. Budget rollover behavior.
5. Credit-card and debt requirements.
6. Gmail initial query configuration UX and historical lookback.
7. Raw-email retention period.
8. Supported banks/email templates for alpha.
9. Hosting provider and deployment region.
10. Whether an external LLM is allowed to process redacted email content.
11. Whether Flutter should support offline financial writes in MVP.
12. Final product name.
