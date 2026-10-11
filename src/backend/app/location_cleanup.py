import sys
import time

from sqlalchemy.orm import Session

from app.database import engine
from app.routers.location import expire_sessions


def cleanup_once() -> None:
    with Session(engine) as db:
        expire_sessions(db)
        db.commit()


def main() -> None:
    while True:
        try:
            cleanup_once()
        except Exception as exc:
            # A database restart must not kill the worker; expiry resumes next pass.
            print(f"location cleanup: {type(exc).__name__}", file=sys.stderr)
        time.sleep(15)


if __name__ == "__main__":
    main()
