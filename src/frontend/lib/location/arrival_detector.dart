import 'dart:math' as math;

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

class ArrivalArea {
  const ArrivalArea({required this.id, required this.vertices});
  final String id;
  final List<GeoPoint> vertices;
}

class PositionObservation {
  const PositionObservation({
    required this.point,
    required this.accuracy,
    required this.elapsed,
  });
  final GeoPoint point;
  final double accuracy;
  final Duration elapsed;
}

/// Mirrors `src/backend/app/location_arrivals.py`; see that file for the rules.
const maxAccuracyMetres = 100.0;
const insideToleranceMetres = 15.0;
const outsideMinimumMetres = 30.0;
const dwell = Duration(seconds: 30);
const maxSilence = Duration(minutes: 3);

enum _Phase { unknown, starting, outside, entering, notified }

class _AreaState {
  _Phase phase = _Phase.unknown;
  Duration since = Duration.zero;
  Duration last = Duration.zero;
}

class ArrivalDetector {
  ArrivalDetector(List<ArrivalArea> areas) : _areas = List.unmodifiable(areas);
  final List<ArrivalArea> _areas;
  final Map<String, _AreaState> _states = {};
  Duration? _lastObservation;

  List<String> observe(PositionObservation observation) {
    final previous = _lastObservation;
    if (previous != null && observation.elapsed <= previous) return const [];
    _lastObservation = observation.elapsed;
    final now = observation.elapsed;
    final arrivals = <String>[];
    for (final area in _areas) {
      final state = _states.putIfAbsent(area.id, _AreaState.new);
      if (state.phase == _Phase.notified) continue;
      final inside = confidentMembership(
        area.vertices,
        observation.point,
        observation.accuracy,
      );
      if (inside == null) continue;
      switch (state.phase) {
        case _Phase.unknown:
          state.phase = inside ? _Phase.starting : _Phase.outside;
        case _Phase.starting:
          if (!inside) state.phase = _Phase.outside;
        case _Phase.outside:
          if (inside) {
            state
              ..phase = _Phase.entering
              ..since = now
              ..last = now;
          }
        case _Phase.entering:
          if (!inside) {
            state.phase = _Phase.outside;
            continue;
          }
          if (now - state.last > maxSilence) state.since = now;
          state.last = now;
          if (now - state.since >= dwell) {
            state.phase = _Phase.notified;
            arrivals.add(area.id);
          }
        case _Phase.notified:
          break;
      }
    }
    return arrivals;
  }
}

/// True inside, false clearly outside, null when the reading cannot tell.
bool? confidentMembership(
  List<GeoPoint> vertices,
  GeoPoint point,
  double accuracy,
) {
  if (vertices.length < 3 ||
      !accuracy.isFinite ||
      accuracy <= 0 ||
      accuracy > maxAccuracyMetres ||
      !point.latitude.isFinite ||
      !point.longitude.isFinite) {
    return null;
  }
  const metresPerDegree = 111320.0;
  final longitudeScale =
      metresPerDegree * math.cos(point.latitude * math.pi / 180);
  final points = vertices
      .map(
        (vertex) => (
          (vertex.longitude - point.longitude) * longitudeScale,
          (vertex.latitude - point.latitude) * metresPerDegree,
        ),
      )
      .toList();
  var inside = false;
  var nearest = double.infinity;
  for (var i = 0; i < points.length; i++) {
    final (ax, ay) = points[i];
    final (bx, by) = points[(i + 1) % points.length];
    final dx = bx - ax;
    final dy = by - ay;
    final lengthSquared = dx * dx + dy * dy;
    final t = lengthSquared == 0
        ? 0.0
        : (-(ax * dx + ay * dy) / lengthSquared).clamp(0.0, 1.0);
    nearest = math.min(
      nearest,
      math.sqrt(math.pow(ax + t * dx, 2) + math.pow(ay + t * dy, 2)),
    );
    if ((ay > 0) != (by > 0) && 0 < ax + (bx - ax) * (-ay) / (by - ay)) {
      inside = !inside;
    }
  }
  if (inside || nearest <= math.min(insideToleranceMetres, accuracy / 2)) {
    return true;
  }
  if (nearest >= math.max(outsideMinimumMetres, accuracy)) return false;
  return null;
}
