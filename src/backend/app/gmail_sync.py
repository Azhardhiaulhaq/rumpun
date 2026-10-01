"""Check due Gmail connections and pending classifications from a scheduler."""

import sys
import uuid
from collections.abc import Callable
from datetime import timedelta

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.database import SessionLocal
from app.errors import ApiError
from app.gmail_integration import GmailProvider, sync_connection
from app.gmail_processing import (
    AccountSuggester,
    JevClassifier,
    TransactionClassifier,
    process_pending,
)
from app.models import GmailConnection, GmailMessage, GmailOAuthAttempt, GmailSyncJob, utcnow


def _suggester(classifier: TransactionClassifier | None) -> AccountSuggester | None:
    # Jev answers both questions; a test classifier may only answer one.
    return classifier if hasattr(classifier, "suggest") else None  # type: ignore[return-value]


def _awaiting(db: Session, connection_id: uuid.UUID) -> int:
    return (
        db.scalar(
            select(func.count(GmailMessage.id)).where(
                GmailMessage.connection_id == connection_id,
                GmailMessage.state == "awaiting_jev",
            )
        )
        or 0
    )


def run_sync_job(
    db: Session,
    job_id: uuid.UUID,
    settings: Settings,
    provider: GmailProvider,
    classifier: TransactionClassifier | None,
) -> bool:
    """Run one requested lookback and record its outcome on the job.

    Candidates are committed as they are created, so the job's count is saved
    after every pass and survives a later failure. Messages that could not be
    classified stay queued for the scheduled pass and are reported on the job
    instead of failing a sync that otherwise worked. Returns False only when
    the job itself failed.
    """
    job = db.scalar(select(GmailSyncJob).where(GmailSyncJob.id == job_id).with_for_update())
    if job is None or job.status != "pending":
        return True
    job.status = "running"
    job.started_at = utcnow()
    db.commit()
    succeeded = True
    try:
        job.discovered_count = sync_connection(
            db, job.connection_id, settings, provider, lookback_days=job.days
        )
        db.commit()
        if classifier is not None:
            while True:
                before = _awaiting(db, job.connection_id)
                if before == 0:
                    break
                result = process_pending(
                    db, job.connection_id, settings, provider, classifier, _suggester(classifier)
                )
                job.candidate_count += result.created
                db.commit()
                if _awaiting(db, job.connection_id) >= before:
                    break
        job.unclassified_count = _awaiting(db, job.connection_id) if classifier else 0
        job.status = "complete"
    except Exception as exc:
        db.rollback()
        refreshed = db.get(GmailSyncJob, job_id)
        if refreshed is None:
            return False
        job = refreshed
        job.status = "failed"
        job.error_code = exc.code if isinstance(exc, ApiError) else type(exc).__name__
        succeeded = False
    job.completed_at = utcnow()
    db.commit()
    return succeeded


def _run_manual_jobs(
    settings: Settings,
    provider: GmailProvider,
    classifier_factory: Callable[[], TransactionClassifier | None],
) -> int:
    failures = 0
    with SessionLocal() as db:
        job_ids = list(
            db.scalars(
                select(GmailSyncJob.id)
                .where(GmailSyncJob.status == "pending")
                .order_by(GmailSyncJob.created_at)
                .limit(20)
            )
        )
    for job_id in job_ids:
        with SessionLocal() as db:
            if not run_sync_job(db, job_id, settings, provider, classifier_factory()):
                job = db.get(GmailSyncJob, job_id)
                code = job.error_code if job is not None else "missing"
                print(f"manual gmail sync {job_id}: {code}", file=sys.stderr)
                failures += 1
    return failures


def run() -> int:
    settings = get_settings()
    cutoff = utcnow() - timedelta(minutes=settings.gmail_sync_minutes)
    with SessionLocal() as db:
        db.query(GmailOAuthAttempt).filter(GmailOAuthAttempt.expires_at < utcnow()).delete()
        db.commit()
        due_ids = list(
            db.scalars(
                select(GmailConnection.id).where(
                    GmailConnection.status == "active",
                    or_(
                        GmailConnection.last_synced_at.is_(None),
                        GmailConnection.last_synced_at <= cutoff,
                    ),
                )
            )
        )
    api_key = settings.jev_api_key

    def classifier_factory() -> TransactionClassifier | None:
        return JevClassifier(api_key) if api_key else None

    failures = 0
    provider = GmailProvider()
    failures += _run_manual_jobs(settings, provider, classifier_factory)
    for connection_id in due_ids:
        with SessionLocal() as db:
            try:
                sync_connection(db, connection_id, settings, provider)
            except Exception as exc:
                db.rollback()
                failures += 1
                detail = exc.code if isinstance(exc, ApiError) else type(exc).__name__
                print(f"gmail sync {connection_id}: {detail}", file=sys.stderr)
    classifier = classifier_factory()
    if classifier is not None:
        with SessionLocal() as db:
            connection_ids = list(
                db.scalars(select(GmailConnection.id).where(GmailConnection.status == "active"))
            )
        for connection_id in connection_ids:
            with SessionLocal() as db:
                try:
                    result = process_pending(
                        db, connection_id, settings, provider, classifier, _suggester(classifier)
                    )
                except Exception as exc:
                    db.rollback()
                    failures += 1
                    print(
                        f"gmail classification {connection_id}: {type(exc).__name__}",
                        file=sys.stderr,
                    )
                    continue
                if result.failed:
                    print(
                        f"gmail classification {connection_id}: "
                        f"{result.failed} messages left for retry",
                        file=sys.stderr,
                    )
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(run())
