import threading
import time
from collections import defaultdict, deque
from collections.abc import Callable

from fastapi import Request

from app.config import get_settings
from app.errors import ApiError


class InMemoryRateLimiter:
    """Process-local abuse protection; production needs a shared Redis or gateway limiter."""

    def __init__(self) -> None:
        self._events: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def clear(self) -> None:
        with self._lock:
            self._events.clear()

    def check(self, key: str, limit: int, window_seconds: int) -> None:
        now = time.monotonic()
        with self._lock:
            events = self._events[key]
            while events and events[0] <= now - window_seconds:
                events.popleft()
            if len(events) >= limit:
                raise ApiError(429, "rate_limit_exceeded", "Too many requests")
            events.append(now)


limiter = InMemoryRateLimiter()


def sensitive_endpoint(name: str) -> Callable[[Request], None]:
    def dependency(request: Request) -> None:
        settings = get_settings()
        client = request.client.host if request.client else "unknown"
        limiter.check(
            f"{name}:{client}", settings.rate_limit_attempts, settings.rate_limit_window_seconds
        )

    return dependency
