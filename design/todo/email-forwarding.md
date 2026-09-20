# Finish email forwarding

Paused 20 Sep 2026, waiting on a domain.

Everything on the Rumpun side is built and tested.
The missing piece is the transport between Gmail and the API: a domain that can receive mail, and something that turns an incoming message into an HTTP call.

## Where it stopped, and why

`in.rumpun.app` was my invention as a default, and it turned out to belong to somebody else: a live site at `rumpun.app` serving "Rumpunara", with Google Workspace mail, a real DKIM key, and `DMARC p=reject`.
The setup was abandoned at Cloudflare's nameserver step, which is the right place for it to stop, and no DNS was changed.

The default is now `invalid.example`, reserved by RFC 6761 so it can never be registered.
An install that forgets to configure this produces an obviously broken address rather than quietly mailing a stranger's domain.

## What is already done

- `POST /api/v1/inbound/email`, HMAC-SHA256 signed over the raw body, constant-time compared
- Per-household addresses with rotation, and mail to an unknown address accepted and dropped rather than refused
- The parser, including the balance-versus-transaction fix and Gmail confirmation-code capture
- The Cloudflare Worker, at `infra/cloudflare-email-worker/worker.js`, syntax checked but never deployed
- The setup screen in the app, under Profil, then Catatan dari email
- 81 backend and 62 frontend tests, and the full path proven through the public ngrok URL

## Steps remaining

### 1. Register a domain

Anywhere is fine; compare the **renewal** price rather than the first year.
Roughly $1 to $3 a year for a `.xyz`.

Nobody will ever read this mailbox, so the name does not matter much.
Avoid `.app` and `.dev`, which are HSTS-preloaded and add friction for no benefit here, and avoid reusing "rumpun" in a way that collides with the existing Rumpunara site.

Buying at Cloudflare skips the nameserver step entirely, which is where this got stuck last time.
Buying elsewhere is fine as long as the nameservers are then pointed at Cloudflare.

Watch for the ICANN verification email after registering, or the domain is suspended after 15 days.

### 2. Enable Cloudflare Email Routing

On the new zone, not on anything with real mail.
Email Routing replaces the apex MX for the whole zone, which is the detail that made `rumpun.app` unsafe.

### 3. Deploy the Worker

Paste `infra/cloudflare-email-worker/worker.js` into a Worker named `rumpun-email`, then add two secrets and deploy again so they take effect:

| Name | Value |
|---|---|
| `RUMPUN_API_URL` | the public URL of `/api/v1/inbound/email` |
| `RUMPUN_INBOUND_SECRET` | the same value as `RUMPUN_INBOUND_WEBHOOK_SECRET` in `src/backend/.env` |

### 4. Route mail to it

A catch-all rule, sending to the Worker.
Catch-all rather than a single address, because a per-address rule breaks every time the address is rotated.

### 5. Point Rumpun at the domain

One variable in `src/backend/.env`, then restart:

```
RUMPUN_INBOUND_EMAIL_DOMAIN=yourdomain.xyz
```

No migration is needed.
The database stores only the local part, currently `rumpun-3fcb5a9bb4c1`, and the domain is glued on when the address is read.
The existing address keeps working under the new domain.

### 6. Verify with Gmail

Add the address as a forwarding address in Gmail, on the web.
Gmail mails a nine-digit code, Rumpun captures it, and it appears on the setup screen.
Paste it back into Gmail, then add a filter forwarding your banks to that address.

Full instructions are in `docs/email-forwarding-setup.md`.

## Decisions already made, for when this is picked up again

**Forwarding instead of reading the mailbox.**
`gmail.readonly` is a restricted scope: Google app verification, and for production a third-party security assessment at roughly $15k to $75k a year.
Forwarding needs none of that.
The cost is a manual Gmail setup, about two minutes per person.

**Cloudflare rather than Hostinger for the mail side.**
Hostinger sells mailboxes, not webhooks, and Rumpun has no IMAP poller by design.
An IMAP loop would mean storing mailbox credentials in the backend and polling instead of push.
Registering the domain at Hostinger is fine; the nameservers just need to point at Cloudflare.

**The address is a secret, like a webhook URL.**
Anyone holding it can create candidates, so it is generated with `secrets.token_hex` and can be rotated.

## Known limits, worth saying out loud when this ships

Forwarding only catches mail arriving after the filter exists.
There is no backfill, because Rumpun never had access to the history.

If a bank changes its sending domain the filter stops matching and Rumpun simply stops receiving that bank.
Nothing errors.
The message count on the setup screen is the only signal.

Rotating the address disables the old one immediately, and the Gmail filter has to be updated by hand or forwarding silently stops.
