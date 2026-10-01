"""Ask Jev to suggest accounts and categories for candidates still in review.

New Gmail candidates get suggestions as they arrive. This fills in the ones
created before suggestions existed. It only fills empty fields, refetches the
email from Gmail because bodies are not stored, and also settles each
candidate's state so cards the parser blocked become confirmable.

Usage, inside the backend container:
    python scripts/suggest_open_candidates.py [--dry-run]
"""

import argparse
import sys

from sqlalchemy import select

from app.candidate_rules import settle_state, transaction_type
from app.config import get_settings
from app.database import SessionLocal
from app.gmail_integration import GmailMessageGone, GmailProvider, decrypt_refresh_token
from app.gmail_processing import (
    JevClassifier,
    _decoded_body,
    _header,
    apply_suggestion,
    suggestion_options,
)
from app.models import CandidateState, GmailConnection, TransactionCandidate
from app.parsing import strip_html


def main(dry_run: bool) -> int:
    settings = get_settings()
    if not settings.jev_api_key:
        print("RUMPUN_JEV_API_KEY is not set", file=sys.stderr)
        return 1
    jev = JevClassifier(settings.jev_api_key)
    provider = GmailProvider()
    counts = {"suggested": 0, "unchanged": 0, "unblocked": 0, "skipped": 0}
    with SessionLocal() as db:
        open_items = list(
            db.scalars(
                select(TransactionCandidate).where(
                    TransactionCandidate.state.in_(
                        [CandidateState.PENDING, CandidateState.NEEDS_INPUT]
                    )
                )
            )
        )
        tokens: dict[object, str] = {}
        for item in open_items:
            source = item.source
            was = item.state
            connection = db.scalar(
                select(GmailConnection).where(
                    GmailConnection.household_id == item.household_id,
                    GmailConnection.status == "active",
                )
            )
            if (
                source.provider != "gmail"
                or connection is None
                or "suggested" in source.metadata_json
            ):
                settle_state(item)
                counts["skipped"] += 1
                counts["unblocked"] += (
                    was == CandidateState.NEEDS_INPUT and item.state == CandidateState.PENDING
                )
                continue
            if connection.id not in tokens:
                tokens[connection.id] = provider.refresh(
                    decrypt_refresh_token(connection.refresh_token_ciphertext, settings), settings
                )
            try:
                email = provider.get(
                    f"messages/{source.provider_message_id}",
                    tokens[connection.id],
                    params={"format": "full"},
                )
            except GmailMessageGone:
                settle_state(item)
                counts["skipped"] += 1
                continue
            body, is_html = _decoded_body(email)
            kind = transaction_type(item)
            accounts, categories = suggestion_options(
                db, item.household_id, connection.user_id, item.proposed_currency, kind
            )
            before = (
                item.proposed_account_id,
                item.proposed_destination_account_id,
                item.proposed_category_id,
            )
            apply_suggestion(
                item,
                source,
                jev.suggest(
                    sender=_header(email, "From"),
                    subject=_header(email, "Subject"),
                    body=strip_html(body) if is_html else body,
                    transaction_type=kind,
                    accounts=accounts,
                    categories=categories,
                ),
            )
            after = (
                item.proposed_account_id,
                item.proposed_destination_account_id,
                item.proposed_category_id,
            )
            counts["suggested" if after != before else "unchanged"] += 1
            counts["unblocked"] += (
                was == CandidateState.NEEDS_INPUT and item.state == CandidateState.PENDING
            )
            if after != before or item.state != was:
                item.version += 1
        if dry_run:
            db.rollback()
        else:
            db.commit()
    print(f"{'Dry run. ' if dry_run else ''}open={len(open_items)} {counts}")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    raise SystemExit(main(parser.parse_args().dry_run))
