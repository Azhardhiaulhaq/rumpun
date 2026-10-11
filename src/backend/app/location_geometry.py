import math

from app.errors import ApiError

Point = tuple[float, float]


def validate_polygon(vertices: list[Point]) -> None:
    if not 3 <= len(vertices) <= 64 or len(set(vertices)) != len(vertices):
        raise ApiError(422, "invalid_polygon", "Use 3 to 64 distinct polygon corners")
    if any(not math.isfinite(v) for point in vertices for v in point):
        raise ApiError(422, "invalid_polygon", "Coordinates must be finite")
    if any(abs(lat) > 85 or abs(lon) > 180 for lat, lon in vertices):
        raise ApiError(422, "invalid_polygon", "Coordinates are outside supported bounds")
    if max(p[0] for p in vertices) - min(p[0] for p in vertices) > 0.2 or (
        max(p[1] for p in vertices) - min(p[1] for p in vertices) > 0.2
    ):
        raise ApiError(422, "invalid_polygon", "Meeting areas must span less than 0.2 degrees")
    edges = list(zip(vertices, vertices[1:] + vertices[:1], strict=True))
    area = sum(a[0] * b[1] - b[0] * a[1] for a, b in edges)
    if abs(area) < 1e-10:
        raise ApiError(422, "invalid_polygon", "Polygon must enclose an area")
    for i, (a, b) in enumerate(edges):
        for j, (c, d) in enumerate(edges):
            if j <= i or j == i + 1 or (i == 0 and j == len(edges) - 1):
                continue
            if _intersects(a, b, c, d):
                raise ApiError(422, "invalid_polygon", "Polygon edges must not cross or touch")


def _cross(a: Point, b: Point, c: Point) -> float:
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def _intersects(a: Point, b: Point, c: Point, d: Point) -> bool:
    if (
        max(a[0], b[0]) < min(c[0], d[0])
        or max(c[0], d[0]) < min(a[0], b[0])
        or max(a[1], b[1]) < min(c[1], d[1])
        or max(c[1], d[1]) < min(a[1], b[1])
    ):
        return False
    return _cross(a, b, c) * _cross(a, b, d) <= 0 and (_cross(c, d, a) * _cross(c, d, b) <= 0)
