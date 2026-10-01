"""Turning a forwarded transaction email into a proposed transaction.

Nothing here writes to the ledger. The output is a proposal with a confidence
score and the evidence behind it, which a person confirms or rejects. When a
field cannot be read with confidence it is left empty rather than guessed: a
missing amount stops the candidate at needs_input, while a wrong amount would
quietly post the wrong number.
"""

from __future__ import annotations

import html
import re
import unicodedata
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta, timezone

PARSER_VERSION = "rumpun-id-2"

# Amounts in Indonesian bank mail: "Rp 286.500", "IDR 1.250.000,00", "Rp286500".
_AMOUNT = re.compile(
    r"(?:rp|idr)\s*\.?\s*"
    r"(?P<integer>[0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]+)"
    r"(?P<fraction>[.,][0-9]{1,2})?(?![0-9]|[.,][0-9])",
    re.IGNORECASE,
)

# Words that mark money arriving rather than leaving. Indonesian banks are
# fairly consistent here, and the direction decides the sign of the posting.
_INCOME_WORDS = (
    "dana masuk",
    "uang masuk",
    "kredit",
    "diterima",
    "penerimaan",
    "top up berhasil",
    "topup berhasil",
    "masuk ke rekening",
    "transfer masuk",
)
_EXPENSE_WORDS = (
    "pembayaran",
    "pembelian",
    "transaksi",
    "debit",
    "penarikan",
    "tarik tunai",
    "dana keluar",
    "uang keluar",
    "transfer keluar",
    "berhasil dibayar",
    "pembayaran berhasil",
    "payment",
    "spent",
    "charged",
    "debit card",
)
_TRANSFER_WORDS = (
    "money arrived in your shared pocket",
    "you have made a transfer",
    " is adding ",
)

# Senders Rumpun recognises, mapped to the name shown on the candidate. An
# unknown sender still produces a candidate; it just scores lower.
_KNOWN_SENDERS = {
    "bca.co.id": "BCA",
    "klikbca.com": "BCA",
    "bankmandiri.co.id": "Mandiri",
    "bni.co.id": "BNI",
    "bri.co.id": "BRI",
    "cimbniaga.co.id": "CIMB Niaga",
    "permatabank.co.id": "Permata",
    "gopay.co.id": "GoPay",
    "gojek.com": "GoPay",
    "ovo.id": "OVO",
    "dana.id": "DANA",
    "shopee.co.id": "ShopeePay",
    "jago.com": "Jago",
    "seabank.co.id": "SeaBank",
}

_MONTHS = {
    "jan": 1,
    "feb": 2,
    "mar": 3,
    "apr": 4,
    "mei": 5,
    "may": 5,
    "jun": 6,
    "jul": 7,
    "agu": 8,
    "aug": 8,
    "sep": 9,
    "okt": 10,
    "oct": 10,
    "nov": 11,
    "des": 12,
    "dec": 12,
}

_DATE_PATTERNS = (
    # 19/09/2026 or 19-09-2026
    re.compile(r"\b(\d{1,2})[/-](\d{1,2})[/-](\d{4})\b"),
    # 19 Sep 2026 / 19 September 2026
    re.compile(r"\b(\d{1,2})\s+([A-Za-z]{3,9})\s+(\d{4})\b"),
)

_TIME = re.compile(r"\b(\d{1,2}):(\d{2})(?::(\d{2}))?\b")

_TAG = re.compile(r"<[^>]+>")
_STYLE_BLOCK = re.compile(r"<(script|style)\b.*?</\1>", re.IGNORECASE | re.DOTALL)


@dataclass
class Evidence:
    """Where a value came from, so a reviewer can check the parser's work."""

    field_name: str
    value: str
    snippet: str


@dataclass
class ParsedEmail:
    amount_atomic: int | None = None
    currency: str = "IDR"
    description: str | None = None
    occurred_at: datetime | None = None
    direction: str = "expense"
    issuer: str | None = None
    confidence_bps: int = 0
    warnings: list[str] = field(default_factory=list)
    evidence: list[dict[str, str]] = field(default_factory=list)

    @property
    def is_complete(self) -> bool:
        return (
            self.amount_atomic is not None
            and self.description is not None
            and self.direction != "transfer"
        )


def strip_html(raw: str) -> str:
    """HTML mail to readable text.

    Banks send tables and inline styles; the numbers matter, the markup does
    not. Script and style bodies are dropped entirely so their contents never
    look like transaction text.
    """
    without_blocks = _STYLE_BLOCK.sub(" ", raw)
    text = _TAG.sub(" ", without_blocks)
    text = html.unescape(text)
    # Non-breaking spaces are common in bank mail and would break the amount
    # pattern if left in place.
    text = text.replace("\xa0", " ")
    text = unicodedata.normalize("NFKC", text)
    return re.sub(r"[ \t]+", " ", text)


def _snippet(text: str, start: int, end: int, width: int = 48) -> str:
    left = max(0, start - width)
    right = min(len(text), end + width)
    return text[left:right].strip()


# Figures that are not the transaction. A balance is usually the largest
# number in the message, so picking the largest would reliably pick the wrong
# one; these words identify the amounts to skip.
_NOT_THE_AMOUNT = (
    "saldo",
    "balance",
    "limit",
    "sisa",
    "total tagihan",
    "biaya admin",
    "biaya",
    "fee",
)

# Words that sit next to the figure that IS the transaction.
_IS_THE_AMOUNT = (
    "sebesar",
    "sejumlah",
    "nominal",
    "jumlah",
    "amount",
    "total bayar",
    "charged a fee of",
)


def _label_before(text: str, start: int, window: int = 42) -> str:
    return text[max(0, start - window) : start].lower()


def parse_amount(text: str) -> tuple[int | None, str | None]:
    """The transaction figure, in minor units.

    Candidates are scored by the words immediately before them rather than by
    size: "Rp 286.500" after "sebesar" is the purchase, while a larger
    "Rp 4.213.500" after "Saldo" is what is left in the account.
    """
    scored: list[tuple[int, int, str]] = []
    for match in _AMOUNT.finditer(text):
        digits = re.sub(r"[.,]", "", match.group("integer"))
        if not digits.isdigit():
            continue
        value = int(digits)
        # IDR has no minor unit in practice, so a trailing ",00" is dropped
        # rather than multiplied in.
        if value <= 0:
            continue
        label = _label_before(text, match.start())
        rank = 0
        if any(word in label for word in _IS_THE_AMOUNT):
            rank = 2
        elif any(word in label for word in _NOT_THE_AMOUNT):
            rank = -1
        scored.append((rank, value, _snippet(text, match.start(), match.end())))
    if not scored:
        return None, None
    best_rank = max(rank for rank, _, _ in scored)
    # Every figure looked like a balance: the message is ambiguous, so no
    # amount is better than a confidently wrong one.
    if best_rank < 0:
        return None, None
    # Among equally-labelled figures the largest is the usual choice, since
    # fees and change are smaller than the purchase.
    candidates = [(value, snip) for rank, value, snip in scored if rank == best_rank]
    value, snippet_text = max(candidates, key=lambda item: item[0])
    return value, snippet_text


def parse_direction(text: str) -> tuple[str, str | None]:
    lowered = text.lower()
    for word in _TRANSFER_WORDS:
        index = lowered.find(word)
        if index != -1:
            return "transfer", _snippet(text, index, index + len(word))
    for word in _INCOME_WORDS:
        index = lowered.find(word)
        if index != -1:
            return "income", _snippet(text, index, index + len(word))
    for word in _EXPENSE_WORDS:
        index = lowered.find(word)
        if index != -1:
            return "expense", _snippet(text, index, index + len(word))
    # Most transaction mail is about money leaving, so that is the safer
    # default; the reviewer sees the direction before confirming either way.
    return "expense", None


def parse_datetime(text: str) -> tuple[datetime | None, str | None]:
    for pattern in _DATE_PATTERNS:
        match = pattern.search(text)
        if match is None:
            continue
        day_raw, month_raw, year_raw = match.groups()
        month = int(month_raw) if month_raw.isdigit() else _MONTHS.get(month_raw[:3].lower(), 0)
        if not 1 <= month <= 12:
            continue
        day, year = int(day_raw), int(year_raw)
        if not 1 <= day <= 31:
            continue
        hour = minute = 0
        time_match = _TIME.search(text, match.end(), match.end() + 40)
        if time_match:
            hour, minute = int(time_match.group(1)), int(time_match.group(2))
            if hour > 23 or minute > 59:
                hour = minute = 0
        try:
            zone = UTC
            if time_match:
                suffix = text[time_match.end() : time_match.end() + 12]
                zone_match = re.search(r"\b(WIB|WITA|WIT)\b", suffix, re.IGNORECASE)
                if zone_match:
                    offset = {"WIB": 7, "WITA": 8, "WIT": 9}[zone_match.group(1).upper()]
                    zone = timezone(timedelta(hours=offset))
            found = datetime(year, month, day, hour, minute, tzinfo=zone).astimezone(UTC)
        except ValueError:
            continue
        return found, _snippet(text, match.start(), match.end())
    return None, None


def parse_description(text: str, subject: str, issuer: str | None) -> tuple[str, str]:
    """A short human label. The subject is usually the clearest summary."""
    cleaned = " ".join(subject.split()).strip()
    # Forwarded mail carries a prefix that says nothing about the purchase.
    cleaned = re.sub(r"^(fwd?|fw|re)\s*:\s*", "", cleaned, flags=re.IGNORECASE).strip()
    if issuer == "BCA" and cleaned.lower() == "internet transaction journal":
        payment = re.search(
            r"\bPayment to\s*:\s*(.{3,80}?)\s+"
            r"(?:Merchant Location|Acquirer|Merchant PAN|Terminal ID)\s*:",
            text,
            re.IGNORECASE,
        )
        if payment:
            return payment.group(1).strip()[:240], "body"
    if cleaned:
        return cleaned[:240], "subject"
    merchant = re.search(
        r"(?:merchant|penerima|kepada|toko|di)\s*[:\-]?\s*([A-Za-z0-9 .,'&-]{3,60})",
        text,
        re.IGNORECASE,
    )
    if merchant:
        return merchant.group(1).strip()[:240], "body"
    if issuer:
        return f"Transaksi {issuer}"[:240], "issuer"
    return "Transaksi dari email", "fallback"


def issuer_for(sender: str) -> str | None:
    domain = sender.rsplit("@", 1)[-1].strip().lower().rstrip(">")
    for known, name in _KNOWN_SENDERS.items():
        if domain == known or domain.endswith("." + known):
            return name
    return None


def parse_transaction_email(
    *,
    sender: str,
    subject: str,
    body: str,
    is_html: bool = False,
) -> ParsedEmail:
    """Reads one forwarded email into a proposal.

    Confidence is built from what could actually be read: an amount is worth
    most, because without it nothing can be posted at all.
    """
    text = strip_html(body) if is_html else body
    result = ParsedEmail()
    result.issuer = issuer_for(sender)

    amount, amount_snippet = parse_amount(text)
    if amount is None:
        result.warnings.append("amount_not_found")
    else:
        result.amount_atomic = amount
        result.evidence.append(
            {
                "field": "amount_atomic",
                "value": str(amount),
                "snippet": amount_snippet or "",
            }
        )

    direction, direction_snippet = parse_direction(text + " " + subject)
    result.direction = direction
    if direction_snippet:
        result.evidence.append(
            {"field": "direction", "value": direction, "snippet": direction_snippet}
        )
        if direction == "transfer":
            result.warnings.append("transfer_needs_account_mapping")
    else:
        result.warnings.append("direction_assumed")

    occurred, date_snippet = parse_datetime(text)
    if occurred is None:
        result.warnings.append("date_not_found")
    else:
        result.occurred_at = occurred
        result.evidence.append(
            {
                "field": "occurred_at",
                "value": occurred.isoformat(),
                "snippet": date_snippet or "",
            }
        )

    description, source = parse_description(text, subject, result.issuer)
    result.description = description
    result.evidence.append({"field": "description", "value": description, "snippet": source})

    if result.issuer is None:
        result.warnings.append("unknown_sender")

    score = 0
    if result.amount_atomic is not None:
        score += 5000
    if result.issuer is not None:
        score += 2000
    if direction_snippet is not None:
        score += 1500
    if occurred is not None:
        score += 1000
    if source == "subject":
        score += 500
    result.confidence_bps = min(score, 10000)
    return result
