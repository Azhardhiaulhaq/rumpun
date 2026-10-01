"""Classify discovered Gmail messages and create review candidates."""

import base64
import hashlib
import re
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, Protocol

import structlog
from sqlalchemy import select
from sqlalchemy.orm import Session
from typesafe_sdk import Choice, Noul, TypeSafeClient

from app.candidate_rules import settle_state
from app.config import Settings
from app.gmail_integration import GmailMessageGone, GmailProvider, decrypt_refresh_token
from app.models import (
    AccountAccessGrant,
    AccountKind,
    CandidateSource,
    CandidateState,
    Category,
    FinancialAccount,
    GmailConnection,
    GmailMessage,
    Household,
    Membership,
    TransactionCandidate,
    User,
)
from app.parsing import PARSER_VERSION, parse_transaction_email, strip_html
from app.push import queue_candidate_review

logger = structlog.get_logger()

_JAGO_SHARED_SPENT = "There was a transaction in your Shared Pocket"
_JAGO_MATCHING_ALERTS = {
    "Money arrived in your Shared Pocket",
    "You have made a transaction using your debit card",
    "You have made a transfer",
}
_JAGO_RECIPIENT = re.compile(
    r"\bTo\s+:?\s*(?P<name>.{2,100}?)\s+"
    r"(?P<account>\d{10,24})\s+Amount\b",
    re.IGNORECASE,
)


def jago_recipient(sender: str, body: str, *, is_html: bool) -> tuple[str, str] | None:
    if "@jago.com" not in sender.lower():
        return None
    content = strip_html(body) if is_html else body
    match = _JAGO_RECIPIENT.search(re.sub(r"\s+", " ", content))
    if match is None:
        return None
    return match.group("name").strip(), match.group("account")


def _specific_jago_alert(subject: object) -> bool:
    return isinstance(subject, str) and (
        subject in _JAGO_MATCHING_ALERTS or subject.startswith("You have made a payment to ")
    )


def _collapse_jago_mirror(
    db: Session,
    connection: GmailConnection,
    source: CandidateSource,
    candidate: TransactionCandidate,
) -> None:
    """Keep one review item when Jago emails both sides of the same movement."""
    if source.sender_domain != "jago.com" or candidate.proposed_amount_atomic is None:
        return
    subject = source.metadata_json.get("subject")
    if subject != _JAGO_SHARED_SPENT and not _specific_jago_alert(subject):
        return
    neighbours = db.execute(
        select(CandidateSource, TransactionCandidate)
        .join(TransactionCandidate, TransactionCandidate.source_id == CandidateSource.id)
        .where(
            CandidateSource.household_id == source.household_id,
            CandidateSource.provider == "gmail",
            CandidateSource.sender_domain == "jago.com",
            CandidateSource.id != source.id,
            CandidateSource.received_at.between(
                source.received_at - timedelta(seconds=2),
                source.received_at + timedelta(seconds=2),
            ),
            TransactionCandidate.proposed_amount_atomic == candidate.proposed_amount_atomic,
            TransactionCandidate.state.in_([CandidateState.PENDING, CandidateState.NEEDS_INPUT]),
        )
    ).all()
    for other_source, other_candidate in neighbours:
        other_subject = other_source.metadata_json.get("subject")
        complementary = (subject == _JAGO_SHARED_SPENT and _specific_jago_alert(other_subject)) or (
            _specific_jago_alert(subject) and other_subject == _JAGO_SHARED_SPENT
        )
        if not complementary:
            continue
        if subject == _JAGO_SHARED_SPENT:
            mirror_source, mirror_candidate = source, candidate
        else:
            mirror_source, mirror_candidate = other_source, other_candidate
        mirror_candidate.state = CandidateState.DUPLICATE
        mirror_candidate.warnings = [*mirror_candidate.warnings, "jago_mirror_alert"]
        mirror_message = db.scalar(
            select(GmailMessage).where(
                GmailMessage.connection_id == connection.id,
                GmailMessage.gmail_message_id == mirror_source.provider_message_id,
            )
        )
        if mirror_message is not None:
            mirror_message.state = "duplicate"
        break


class TransactionClassifier(Protocol):
    def probability(self, *, sender: str, subject: str, body: str) -> float: ...


@dataclass(frozen=True)
class Option:
    """An account or category Jev may pick, by the name the household uses."""

    id: uuid.UUID
    name: str
    description: str


@dataclass(frozen=True)
class Pick:
    id: uuid.UUID
    confidence: float


@dataclass(frozen=True)
class Suggestion:
    account: Pick | None = None
    destination: Pick | None = None
    category: Pick | None = None


class AccountSuggester(Protocol):
    def suggest(
        self,
        *,
        sender: str,
        subject: str,
        body: str,
        transaction_type: str,
        accounts: list[Option],
        categories: list[Option],
    ) -> Suggestion: ...


# Below this a pick is more likely to mislead than help, so the field stays
# empty for the person to choose. A Jago pocket top-up names the pocket that
# received money (picked with certainty) but not the account it left, where
# Jev guessed with 0.43.
SUGGESTION_MIN_CONFIDENCE = 0.6
_UNKNOWN = "Tidak disebut di email"


class JevClassifier:
    def __init__(self, api_key: str) -> None:
        self.api_key = api_key

    def probability(self, *, sender: str, subject: str, body: str) -> float:
        with TypeSafeClient(api_key=self.api_key, model="jev-latest") as client:
            result = client.system_one(
                state={"sender": sender, "subject": subject, "body": body[:30000]},
                questions={
                    "transaction": Noul(
                        instructions=(
                            "Does this email confirm a completed financial transaction "
                            "that a household should record, such as a payment, income, "
                            "transfer, refund, or fee? Exclude advertising, one-time "
                            "passwords, balance-only alerts, statements, and pending or "
                            "failed transactions. Shipping or delivery updates, ticket "
                            "release notices, free orders, and membership status updates "
                            "are not new transactions even if they repeat an order total."
                        )
                    )
                },
            )
            return float(result.nouls["transaction"].noul)

    def suggest(
        self,
        *,
        sender: str,
        subject: str,
        body: str,
        transaction_type: str,
        accounts: list[Option],
        categories: list[Option],
    ) -> Suggestion:
        account_criteria: dict[str, str | None] = {o.name: o.description for o in accounts}
        account_criteria[_UNKNOWN] = "The email does not show which of these accounts it was."
        questions: dict[str, Choice] = {}
        if accounts:
            questions["account"] = Choice(
                instructions=(
                    "Which of the household's accounts received this money?"
                    if transaction_type == "income"
                    else "Which of the household's accounts did this money leave?"
                ),
                criteria=account_criteria,
            )
            if transaction_type == "transfer":
                questions["destination"] = Choice(
                    instructions="Which of the household's accounts received this money?",
                    criteria=account_criteria,
                )
        if categories and transaction_type != "transfer":
            category_criteria: dict[str, str | None] = {o.name: o.description for o in categories}
            category_criteria[_UNKNOWN] = "None of these categories fits."
            questions["category"] = Choice(
                instructions="Which spending category fits this transaction best?"
                if transaction_type == "expense"
                else "Which income category fits this transaction best?",
                criteria=category_criteria,
            )
        if not questions:
            return Suggestion()
        with TypeSafeClient(api_key=self.api_key, model="jev-latest") as client:
            result = client.system_one(
                state={"sender": sender, "subject": subject, "body": body[:30000]},
                questions=questions,
            )

        def pick(name: str, options: list[Option]) -> Pick | None:
            answer = result.choices.get(name)
            if answer is None or answer.confidence < SUGGESTION_MIN_CONFIDENCE:
                return None
            match = next((o for o in options if o.name == answer.choice), None)
            return Pick(match.id, float(answer.confidence)) if match else None

        return Suggestion(
            account=pick("account", accounts),
            destination=pick("destination", accounts),
            category=pick("category", categories),
        )


_SPENDABLE_KINDS = {
    AccountKind.CASH,
    AccountKind.BANK,
    AccountKind.EWALLET,
    AccountKind.CREDIT_CARD,
    AccountKind.BUDGET_ENVELOPE,
    AccountKind.FOREIGN_CURRENCY,
}
_KIND_LABELS = {
    AccountKind.CASH: "Cash",
    AccountKind.BANK: "Bank account",
    AccountKind.EWALLET: "E-wallet",
    AccountKind.CREDIT_CARD: "Credit card",
    AccountKind.BUDGET_ENVELOPE: "Budget pocket inside a bank app",
    AccountKind.FOREIGN_CURRENCY: "Foreign currency account",
}


def suggestion_options(
    db: Session, household_id: uuid.UUID, user_id: uuid.UUID, currency: str, transaction_type: str
) -> tuple[list[Option], list[Option]]:
    """Accounts and categories Jev may choose between for one candidate.

    Only accounts the connection's owner can see are offered, so a suggestion
    never reveals a restricted account. Names that appear twice are left out,
    since a pick by name could not tell them apart.
    """
    granted = select(AccountAccessGrant.account_id).where(
        AccountAccessGrant.household_id == household_id,
        AccountAccessGrant.user_id == user_id,
    )
    rows = list(
        db.scalars(
            select(FinancialAccount)
            .where(
                FinancialAccount.household_id == household_id,
                FinancialAccount.status == "active",
                FinancialAccount.currency == currency,
                FinancialAccount.kind.in_(_SPENDABLE_KINDS),
                (FinancialAccount.visibility == "household") | FinancialAccount.id.in_(granted),
            )
            .order_by(FinancialAccount.name)
        )
    )
    names = [row.name for row in rows]
    accounts = [
        Option(row.id, row.name, f"{_KIND_LABELS[row.kind]} in {row.currency}")
        for row in rows
        if names.count(row.name) == 1
    ]
    categories: list[Option] = []
    if transaction_type in {"expense", "income"}:
        categories = [
            Option(row.id, row.name, row.name)
            for row in db.scalars(
                select(Category)
                .where(
                    Category.household_id == household_id,
                    Category.category_type == transaction_type,
                )
                .order_by(Category.name)
            )
        ]
    return accounts, categories


def apply_suggestion(
    candidate: TransactionCandidate, source: CandidateSource, s: Suggestion
) -> None:
    """Fill only empty fields, so a person's own choice is never overwritten."""
    applied: dict[str, object] = {}
    if s.account and candidate.proposed_account_id is None:
        candidate.proposed_account_id = s.account.id
        applied["account_id"] = str(s.account.id)
    if (
        s.destination
        and candidate.proposed_destination_account_id is None
        and s.destination.id != candidate.proposed_account_id
    ):
        candidate.proposed_destination_account_id = s.destination.id
        applied["destination_account_id"] = str(s.destination.id)
    if s.category and candidate.proposed_category_id is None:
        candidate.proposed_category_id = s.category.id
        applied["category_id"] = str(s.category.id)
    if applied:
        source.metadata_json = {**source.metadata_json, "suggested": applied}
    settle_state(candidate)


@dataclass(frozen=True)
class ClassificationPass:
    """Outcome of one pass over a connection's unclassified messages."""

    created: int = 0
    failed: int = 0


def _decoded_body(payload: dict[str, Any]) -> tuple[str, bool]:
    plain: list[str] = []
    html: list[str] = []

    def visit(part: dict[str, Any]) -> None:
        if part.get("filename"):
            return
        content_type = part.get("mimeType", "")
        data = part.get("body", {}).get("data")
        if isinstance(data, str) and content_type in {"text/plain", "text/html"}:
            encoded = data[:100000]
            decoded = base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)).decode(
                "utf-8", errors="replace"
            )
            (plain if content_type == "text/plain" else html).append(decoded)
        for child in part.get("parts", []):
            visit(child)

    visit(payload.get("payload", {}))
    if plain:
        return "\n".join(plain)[:50000], False
    if html:
        return "\n".join(html)[:50000], True
    return str(payload.get("snippet", ""))[:50000], False


def _header(payload: dict[str, Any], name: str) -> str:
    return next(
        (
            str(header.get("value", ""))
            for header in payload.get("payload", {}).get("headers", [])
            if str(header.get("name", "")).lower() == name.lower()
        ),
        "",
    )


def process_pending(
    db: Session,
    connection_id: uuid.UUID,
    settings: Settings,
    provider: GmailProvider,
    classifier: TransactionClassifier,
    suggester: AccountSuggester | None = None,
) -> ClassificationPass:
    """Classify waiting messages, leaving any that fail to be retried later.

    One slow or failing message must not discard the rest of the pass, so
    failures are counted rather than raised.
    """
    connection = db.scalar(
        select(GmailConnection).where(GmailConnection.id == connection_id).with_for_update()
    )
    if connection is None or connection.status != "active":
        return ClassificationPass()
    membership = db.scalar(
        select(Membership.id).where(
            Membership.user_id == connection.user_id,
            Membership.household_id == connection.household_id,
        )
    )
    user_active = db.scalar(select(User.is_active).where(User.id == connection.user_id))
    if membership is None or not user_active:
        return ClassificationPass()
    household = db.get(Household, connection.household_id)
    if household is None:
        return ClassificationPass()
    pending = list(
        db.scalars(
            select(GmailMessage)
            .where(
                GmailMessage.connection_id == connection.id,
                GmailMessage.state == "awaiting_jev",
            )
            .order_by(GmailMessage.discovered_at)
            .limit(200)
        )
    )
    if not pending:
        return ClassificationPass()
    access_token = provider.refresh(
        decrypt_refresh_token(connection.refresh_token_ciphertext, settings), settings
    )
    created = 0
    failures = 0
    for message in pending:
        existing = db.scalar(
            select(CandidateSource.id).where(
                CandidateSource.household_id == household.id,
                CandidateSource.provider == "gmail",
                CandidateSource.provider_message_id == message.gmail_message_id,
            )
        )
        if existing is not None:
            message.state = "duplicate"
            db.commit()
            continue
        try:
            email = provider.get(
                f"messages/{message.gmail_message_id}", access_token, params={"format": "full"}
            )
        except GmailMessageGone:
            message.state = "gone"
            db.commit()
            continue
        except Exception as exc:
            logger.warning(
                "gmail_message_fetch_failed",
                connection_id=str(connection.id),
                exception_type=type(exc).__name__,
            )
            failures += 1
            continue
        if {"SENT", "DRAFT", "SPAM", "TRASH"} & set(email.get("labelIds", [])):
            message.state = "ignored"
            db.commit()
            continue
        try:
            sender = _header(email, "From")
            subject = _header(email, "Subject")
            body, is_html = _decoded_body(email)
            probability = classifier.probability(sender=sender, subject=subject, body=body)
            if not 0 <= probability <= 1:
                raise ValueError("Jev probability must be between zero and one")
            if probability >= 0.35:
                parsed = parse_transaction_email(
                    sender=sender, subject=subject, body=body, is_html=is_html
                )
                recipient = jago_recipient(sender, body, is_html=is_html)
                if recipient is not None:
                    parsed.description = recipient[0]
                received_at = datetime.fromtimestamp(int(email["internalDate"]) / 1000, UTC)
        except Exception as exc:
            logger.warning(
                "gmail_message_classification_failed",
                connection_id=str(connection.id),
                exception_type=type(exc).__name__,
            )
            failures += 1
            continue
        if probability < 0.35:
            message.state = "ignored"
            db.commit()
            continue
        source = CandidateSource(
            household_id=household.id,
            provider="gmail",
            provider_message_id=message.gmail_message_id,
            sender_domain=sender.rsplit("@", 1)[-1].lower().rstrip(">")[:255],
            received_at=received_at,
            content_hash=hashlib.sha256(f"{sender}|{subject}|{body}".encode()).hexdigest(),
            parser_version=PARSER_VERSION,
            metadata_json={
                "subject": subject[:240],
                "issuer": parsed.issuer,
                "direction": parsed.direction,
                "jev_probability_bps": round(probability * 10000),
                **(
                    {"recipient_name": recipient[0], "recipient_account": recipient[1]}
                    if recipient is not None
                    else {}
                ),
            },
        )
        db.add(source)
        db.flush()
        warnings = list(parsed.warnings)
        if probability < 0.7:
            warnings.append("jev_uncertain")
        candidate = TransactionCandidate(
            household_id=household.id,
            source_id=source.id,
            state=CandidateState.NEEDS_INPUT,
            confidence_bps=min(parsed.confidence_bps, round(probability * 10000)),
            warnings=warnings,
            evidence=list(parsed.evidence),
            proposed_amount_atomic=parsed.amount_atomic,
            proposed_currency=parsed.currency,
            proposed_description=parsed.description,
            proposed_occurred_at=parsed.occurred_at or received_at,
            proposed_type=parsed.direction
            if parsed.direction in {"expense", "income", "transfer"}
            else "expense",
        )
        db.add(candidate)
        db.flush()
        settle_state(candidate)
        if suggester is not None:
            # A suggestion is a convenience. When Jev cannot answer, the
            # candidate still arrives and the person picks the accounts.
            try:
                accounts, categories = suggestion_options(
                    db,
                    household.id,
                    connection.user_id,
                    candidate.proposed_currency,
                    candidate.proposed_type or "expense",
                )
                apply_suggestion(
                    candidate,
                    source,
                    suggester.suggest(
                        sender=sender,
                        subject=subject,
                        body=strip_html(body) if is_html else body,
                        transaction_type=candidate.proposed_type or "expense",
                        accounts=accounts,
                        categories=categories,
                    ),
                )
            except Exception as exc:
                logger.warning(
                    "gmail_suggestion_failed",
                    connection_id=str(connection.id),
                    exception_type=type(exc).__name__,
                )
        message.state = "candidate"
        _collapse_jago_mirror(db, connection, source, candidate)
        queue_candidate_review(db, candidate, connection.user_id)
        db.commit()
        created += 1
    return ClassificationPass(created=created, failed=failures)
