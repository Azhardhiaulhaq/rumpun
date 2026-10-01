"""Deliver committed notification events using Firebase credentials from ADC."""

import sys

from app.config import get_settings
from app.database import SessionLocal
from app.push import FirebaseSender, dispatch_pending


def run() -> int:
    project_id = get_settings().firebase_project_id
    if not project_id:
        return 0
    try:
        sender = FirebaseSender(project_id)
        with SessionLocal() as db:
            dispatch_pending(db, sender)
    except Exception as exc:
        print(f"push delivery: {type(exc).__name__}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
