# Turning on transaction email

Rumpun turns bank notification emails into transactions you review before they reach your ledger.
This page is the operational checklist: what has to exist, who does what, and how to tell it is working.

## What this is, and what it is not

Rumpun never opens your mailbox.
It receives only the mail you forward to it.

That is a deliberate design choice, not a missing feature.
Reading a Gmail inbox requires the `gmail.readonly` scope, which Google classes as restricted: it needs app verification, a published privacy policy, a demo video, and for production use a third-party security assessment that runs from roughly $15,000 to $75,000 per year.
Forwarding needs none of that.
The cost is a one-time manual setup in Gmail, about two minutes per person.

## Before you start

Three things have to be in place.
The first two are one-time infrastructure; the third is per household.

### 1. A domain that can receive mail

Pick a subdomain for inbound mail only, for example `mail.example.com`.
Keep it separate from the domain you send from, so an inbound misconfiguration cannot affect outgoing delivery.

Set it in the backend environment:

```sh
RUMPUN_INBOUND_EMAIL_DOMAIN=mail.example.com
```

### 2. A mail provider that posts inbound mail to a webhook

Rumpun does not run an SMTP server.
It expects a provider to accept the mail and `POST` it as JSON.
Mailgun Routes, SendGrid Inbound Parse, Postmark, and Cloudflare Email Workers all do this.

Point the provider's MX records at the subdomain, then configure it to forward everything to:

```
POST https://your-api/api/v1/inbound/email
```

The body must carry these fields:

| Field | Meaning |
|---|---|
| `to` | the Rumpun address the mail was sent to |
| `sender` | who the bank sent it from |
| `subject` | the subject line |
| `text` or `html` | the body; `text` is preferred |
| `message_id` | the provider's message id, used to drop redelivered mail |
| `received_at` | optional; defaults to arrival time |

### 3. The webhook secret

The endpoint is called by a machine, not a signed-in person, so it is authenticated with an HMAC.
Generate a secret and give the same value to Rumpun and to your mail provider:

```sh
openssl rand -hex 32
```

```sh
RUMPUN_INBOUND_WEBHOOK_SECRET=<that value>
```

The provider must send `X-Rumpun-Signature`, holding the hex HMAC-SHA256 of the **raw request body** using that secret.
Rumpun compares it in constant time and rejects anything that does not match.

Without this variable the endpoint returns `503` and accepts nothing.
It never runs unauthenticated, because anyone who could call it could inject transactions.

## Per household, in the app

Open **Profil, then Catatan dari email**.
Only an owner or admin sees the setup button.

1. **Buat alamat rumah** issues an address such as `rumpun-a7f3c2b81d04@mail.example.com`.
   The random part is not decoration: anyone who learns the address can create candidates in that household, so treat it like a password.

2. In **Gmail on the web**, open Settings, then Forwarding and POP/IMAP, then Add a forwarding address, and paste it.

3. Gmail mails a nine-digit confirmation code to that address.
   Because Rumpun receives that mail, it recognises it, stores the code, and shows it on the same setup screen.
   Pull down to refresh, then paste the code back into Gmail.
   Nobody has to go digging for it.

4. In Gmail, open Settings, then Filters, then Create a new filter.
   Put your banks in the From field and choose Forward it to the Rumpun address.
   The setup screen offers a starting filter you can copy:

   ```
   from:(bca.co.id OR bankmandiri.co.id OR gopay.co.id)
   ```

   Forward only what you want Rumpun to see.
   A filter that forwards everything works, but it sends Rumpun mail it has no reason to hold.

## Checking that it works

The address reports its own state.
Before any mail arrives it reads **Menunggu email pertama**; once a message lands it flips to **Sudah jalan** and counts what it has received.

A forwarded bank email should appear under **Tinjau** within a few seconds.
Nothing reaches your balances until you confirm it there.

To verify without waiting for a bank, sign a request by hand:

```sh
BODY='{"to":"rumpun-xxxx@mail.example.com","sender":"noreply@bca.co.id","subject":"Notifikasi Transaksi","text":"Pembayaran sebesar Rp 286.500 pada 19/09/2026 14:23","message_id":"test-1"}'
SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$RUMPUN_INBOUND_WEBHOOK_SECRET" | sed 's/.*= //')
curl -X POST https://your-api/api/v1/inbound/email \
  -H 'Content-Type: application/json' \
  -H "X-Rumpun-Signature: $SIG" \
  -d "$BODY"
```

A working setup answers `{"status":"candidate_created", ...}`.

## What the parser does and does not read

It reads Indonesian bank and e-wallet mail: the amount, the direction, the date, and a description taken from the subject.
It recognises BCA, Mandiri, BNI, BRI, CIMB Niaga, Permata, GoPay, OVO, DANA, ShopeePay, Jago, and SeaBank by sender, and mail from an unknown sender still becomes a candidate at a lower confidence.

Two behaviours are worth knowing because they are deliberate.

**It prefers the transaction over the balance.**
Bank mail usually contains both, and the balance is normally the larger number, so picking the largest figure would reliably pick the wrong one.
Rumpun scores each figure by the words next to it: an amount after "sebesar" is the purchase, one after "Saldo" is not.

**It leaves a field empty rather than guessing.**
When every figure in a message looks like a balance, no amount is proposed at all.
The candidate then sits in `needs_input`, where a person supplies the number.
An empty field is an obvious problem; a confident wrong number is not.

Every field it does read carries the snippet it came from, so you can see why it said what it said.

## Limits to plan around

Forwarding only catches mail that arrives **after** the filter exists.
There is no way to backfill history, because Rumpun never had access to it.

If a bank changes its sending domain, the filter stops matching and Rumpun simply stops receiving that bank.
Nothing errors, so it is worth glancing at the message count on the setup screen occasionally.

Rotating the address disables the old one immediately.
The Gmail filter has to be updated by hand, or forwarding silently stops.
