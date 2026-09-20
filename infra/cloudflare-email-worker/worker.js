/**
 * Cloudflare Email Worker: Gmail to Rumpun.
 *
 * Cloudflare accepts the SMTP delivery, this worker turns the message into
 * JSON and posts it to Rumpun's inbound webhook. Rumpun has no SMTP server of
 * its own, so this is the bridge between the two.
 *
 * The request is signed with HMAC-SHA256 over the exact bytes sent, because
 * the endpoint is called by a machine rather than a signed-in person, and
 * anything that can call it can create transactions.
 *
 * Secrets live in the Worker's environment, never in this file:
 *   RUMPUN_API_URL        https://your-api/api/v1/inbound/email
 *   RUMPUN_INBOUND_SECRET the same value as RUMPUN_INBOUND_WEBHOOK_SECRET
 */

/** Reads a ReadableStream into a string, which is how Cloudflare hands over the raw message. */
async function readAll(stream) {
  const reader = stream.getReader();
  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    total += value.length;
    // A runaway attachment must not exhaust the worker's memory. Bank mail is
    // small; anything past this is not a transaction notification.
    if (total > 2_000_000) break;
  }
  const merged = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    merged.set(chunk, offset);
    offset += chunk.length;
  }
  return new TextDecoder().decode(merged);
}

/**
 * Pulls the readable parts out of a raw RFC 822 message.
 *
 * This is deliberately minimal: Rumpun's parser only needs the text, and a
 * full MIME implementation would be a large dependency for a job this small.
 * Gmail forwards are usually multipart with a text/plain part, so that part is
 * preferred and the HTML is kept as a fallback.
 */
function extractBodies(raw) {
  const separator = raw.indexOf('\r\n\r\n') !== -1 ? '\r\n\r\n' : '\n\n';
  const split = raw.indexOf(separator);
  const headerBlock = split === -1 ? raw : raw.slice(0, split);
  const body = split === -1 ? '' : raw.slice(split + separator.length);

  const boundaryMatch = headerBlock.match(/boundary="?([^";\r\n]+)"?/i);
  if (!boundaryMatch) {
    const isHtml = /content-type:\s*text\/html/i.test(headerBlock);
    const decoded = decodePart(body, headerBlock);
    return isHtml ? { text: null, html: decoded } : { text: decoded, html: null };
  }

  const parts = body.split('--' + boundaryMatch[1]);
  let text = null;
  let html = null;
  for (const part of parts) {
    const partSplit = part.indexOf(separator);
    if (partSplit === -1) continue;
    const partHeaders = part.slice(0, partSplit);
    const partBody = part.slice(partSplit + separator.length);
    if (/content-type:\s*text\/plain/i.test(partHeaders) && text === null) {
      text = decodePart(partBody, partHeaders);
    } else if (/content-type:\s*text\/html/i.test(partHeaders) && html === null) {
      html = decodePart(partBody, partHeaders);
    }
  }
  return { text, html };
}

/**
 * Undoes quoted-printable and base64 transfer encoding.
 *
 * Indonesian bank mail is full of soft line breaks and =XX escapes, and an
 * amount split across one of those would be unreadable to the parser.
 */
function decodePart(body, headers) {
  const encoding = (headers.match(/content-transfer-encoding:\s*([^\s;\r\n]+)/i) || [])[1];
  const lowered = (encoding || '').toLowerCase();
  if (lowered === 'base64') {
    try {
      const binary = atob(body.replace(/\s/g, ''));
      const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
      return new TextDecoder().decode(bytes);
    } catch {
      return body;
    }
  }
  if (lowered === 'quoted-printable') {
    return body
      .replace(/=\r?\n/g, '')
      .replace(/=([0-9A-Fa-f]{2})/g, (_, hex) =>
        String.fromCharCode(parseInt(hex, 16)),
      );
  }
  return body;
}

/** Decodes an RFC 2047 encoded header, so a subject is not "=?UTF-8?B?...?=". */
function decodeHeader(value) {
  if (!value) return '';
  return value.replace(
    /=\?([^?]+)\?([BbQq])\?([^?]*)\?=/g,
    (whole, _charset, kind, data) => {
      try {
        if (kind.toUpperCase() === 'B') {
          const binary = atob(data);
          const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
          return new TextDecoder().decode(bytes);
        }
        return data
          .replace(/_/g, ' ')
          .replace(/=([0-9A-Fa-f]{2})/g, (_m, hex) =>
            String.fromCharCode(parseInt(hex, 16)),
          );
      } catch {
        return whole;
      }
    },
  );
}

function headerValue(raw, name) {
  // Header values continue onto following lines when those lines are indented.
  const pattern = new RegExp(`^${name}:\\s*(.*(?:\\r?\\n[ \\t].*)*)`, 'im');
  const match = raw.match(pattern);
  return match ? match[1].replace(/\r?\n[ \t]+/g, ' ').trim() : '';
}

async function sign(secret, body) {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(body),
  );
  return [...new Uint8Array(signature)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

export default {
  async email(message, env) {
    const raw = await readAll(message.raw);
    const { text, html } = extractBodies(raw);

    // message.from is the envelope sender, which for a Gmail forward is the
    // original bank rather than the person forwarding. That is what Rumpun
    // needs in order to recognise the issuer.
    const payload = {
      to: message.to,
      sender: message.from,
      subject: decodeHeader(headerValue(raw, 'Subject')).slice(0, 998),
      text: text,
      html: html,
      // Used by Rumpun to drop redelivered mail, so a provider retry cannot
      // create the same transaction twice.
      message_id: headerValue(raw, 'Message-ID').slice(0, 255) || null,
      received_at: new Date().toISOString(),
    };

    // Signed over the exact bytes that get sent: re-serialising on either side
    // would change the whitespace and break the comparison.
    const body = JSON.stringify(payload);
    const signature = await sign(env.RUMPUN_INBOUND_SECRET, body);

    const response = await fetch(env.RUMPUN_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Rumpun-Signature': signature,
        // ngrok serves a warning interstitial to browsers without this.
        'ngrok-skip-browser-warning': 'true',
      },
      body,
    });

    if (!response.ok) {
      const detail = await response.text();
      // Throwing tells Cloudflare the delivery failed, so it retries rather
      // than dropping a transaction silently.
      throw new Error(`Rumpun rejected the message: ${response.status} ${detail}`);
    }
  },
};
