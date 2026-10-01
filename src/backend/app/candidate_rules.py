"""Rules about a transaction candidate that both ingestion and review share."""

from app.models import CandidateState, TransactionCandidate


def transaction_type(item: TransactionCandidate) -> str:
    direction = item.source.metadata_json.get("direction") if item.source else None
    return item.proposed_type or (direction if isinstance(direction, str) else None) or "expense"


def is_complete(item: TransactionCandidate) -> bool:
    """Whether the proposal holds everything the confirm sheet cannot supply.

    Accounts and the category are picked while confirming, so only the email's
    own facts can leave a candidate needing input. The parser flags transfers
    because the email does not name the household's accounts, but that is
    something the person confirming chooses, not a reason to block them. The
    state follows the data, so filling a field in moves the card on.
    """
    if not (
        item.proposed_amount_atomic and item.proposed_description and item.proposed_occurred_at
    ):
        return False
    return not (
        transaction_type(item) == "transfer"
        and item.proposed_account_id is not None
        and item.proposed_account_id == item.proposed_destination_account_id
    )


def settle_state(item: TransactionCandidate) -> None:
    """Move an open candidate between pending and needs-input to match its data."""
    if item.state in {CandidateState.PENDING, CandidateState.NEEDS_INPUT}:
        item.state = CandidateState.PENDING if is_complete(item) else CandidateState.NEEDS_INPUT
