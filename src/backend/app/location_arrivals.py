"""Confirm saved-area arrivals from the positions a sharing phone uploads.

The phone already sends its latest position every 10 to 40 seconds, so the
server can recognise an arrival without trusting a device-side detector. Each
session keeps only a small per-area state, never a route.

Rules, tuned for indoor GPS rather than open-sky precision:
- A reading counts as inside when its centre is inside the polygon, or just
  outside it by less than half its accuracy (at most 15 m).
- A reading counts as outside only when its centre is clearly away from the
  boundary, by at least its accuracy and never less than 30 m.
- Anything else, or accuracy worse than 100 m, is uncertain and pauses the
  dwell timer instead of restarting it.
- An area seen inside before ever being seen outside is the starting place and
  does not notify until the member leaves and comes back.
- Thirty seconds of presence confirms an arrival. A silence longer than three
  minutes while entering restarts the dwell, so old readings cannot combine.
"""

import math
from datetime import datetime, timedelta
from typing import Any, Literal

MAX_ACCURACY_M = 100.0
INSIDE_TOLERANCE_M = 15.0
OUTSIDE_MIN_M = 30.0
DWELL = timedelta(seconds=30)
MAX_SILENCE = timedelta(minutes=3)
_METRES_PER_DEGREE = 111_320.0

Membership = Literal["inside", "outside"]


def _locate(vertices: list[list[float]], lat: float, lng: float) -> tuple[bool, float]:
    """Return whether the point is inside and its distance to the boundary in metres."""
    scale = _METRES_PER_DEGREE * math.cos(math.radians(lat))
    points = [((v[1] - lng) * scale, (v[0] - lat) * _METRES_PER_DEGREE) for v in vertices]
    inside = False
    nearest = math.inf
    for (ax, ay), (bx, by) in zip(points, points[1:] + points[:1], strict=True):
        dx, dy = bx - ax, by - ay
        length = dx * dx + dy * dy
        t = 0.0 if length == 0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / length))
        nearest = min(nearest, math.hypot(ax + t * dx, ay + t * dy))
        if (ay > 0) != (by > 0) and ax + (bx - ax) * (-ay) / (by - ay) > 0:
            inside = not inside
    return inside, nearest


def classify(
    vertices: list[list[float]], lat: float, lng: float, accuracy: float
) -> Membership | None:
    if not 0 < accuracy <= MAX_ACCURACY_M or len(vertices) < 3:
        return None
    inside, distance = _locate(vertices, lat, lng)
    if inside or distance <= min(INSIDE_TOLERANCE_M, accuracy / 2):
        return "inside"
    if distance >= max(OUTSIDE_MIN_M, accuracy):
        return "outside"
    return None


def advance(
    areas: list[dict[str, Any]],
    states: dict[str, dict[str, str]],
    *,
    lat: float,
    lng: float,
    accuracy: float,
    observed: datetime,
) -> tuple[dict[str, dict[str, str]], list[tuple[str, datetime]]]:
    """Apply one reading and return the new states plus confirmed (area, arrival time)."""
    updated = {key: dict(value) for key, value in states.items()}
    confirmed: list[tuple[str, datetime]] = []
    stamp = observed.isoformat()
    for area in areas:
        state = updated.setdefault(area["id"], {"phase": "unknown"})
        phase = state["phase"]
        if phase == "notified":
            continue
        membership = classify(area["vertices"], lat, lng, accuracy)
        if membership is None:
            continue
        if phase == "unknown":
            state["phase"] = "starting" if membership == "inside" else "outside"
        elif phase == "starting":
            if membership == "outside":
                state["phase"] = "outside"
        elif membership == "outside":
            updated[area["id"]] = {"phase": "outside"}
        elif phase == "outside":
            updated[area["id"]] = {"phase": "entering", "since": stamp, "last": stamp}
        elif phase == "entering":
            since = datetime.fromisoformat(state["since"])
            if observed - datetime.fromisoformat(state["last"]) > MAX_SILENCE:
                since = observed
            if observed - since >= DWELL:
                updated[area["id"]] = {"phase": "notified"}
                confirmed.append((area["id"], since))
            else:
                updated[area["id"]] = {
                    "phase": "entering",
                    "since": since.isoformat(),
                    "last": stamp,
                }
    return updated, confirmed
