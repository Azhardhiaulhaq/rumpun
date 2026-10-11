import 'package:flutter_test/flutter_test.dart';
import 'package:rumpun_frontend/location/arrival_detector.dart';

/// Same cases as src/backend/tests/test_location_arrivals.py.
void main() {
  // About 66 x 44 m, like the real apartment area.
  const polygon = [
    GeoPoint(-6.2000, 106.8000),
    GeoPoint(-6.2000, 106.8006),
    GeoPoint(-6.2004, 106.8006),
    GeoPoint(-6.2004, 106.8000),
  ];
  const centre = GeoPoint(-6.2002, 106.8003);
  const far = GeoPoint(-6.2050, 106.8003);

  PositionObservation at(int seconds, GeoPoint point, double accuracy) =>
      PositionObservation(
        point: point,
        accuracy: accuracy,
        elapsed: Duration(seconds: seconds),
      );

  List<String> run(List<PositionObservation> readings) {
    final detector = ArrivalDetector([
      const ArrivalArea(id: 'home', vertices: polygon),
    ]);
    return [for (final r in readings) ...detector.observe(r)];
  }

  test('indoor accuracy still counts as inside', () {
    expect(confidentMembership(polygon, centre, 35), isTrue);
    expect(confidentMembership(polygon, centre, 90), isTrue);
    expect(confidentMembership(polygon, far, 40), isFalse);
    expect(confidentMembership(polygon, centre, 150), isNull);
    expect(
      confidentMembership(polygon, const GeoPoint(-6.2006, 106.8003), 40),
      isNull,
    );
  });

  test('starting inside is suppressed until leaving and returning', () {
    expect(
      run([at(0, centre, 10), at(30, centre, 10), at(90, centre, 10)]),
      isEmpty,
    );
    expect(
      run([
        at(0, centre, 10),
        at(30, far, 10),
        at(60, centre, 30),
        at(95, centre, 30),
      ]),
      ['home'],
    );
  });

  test('poor readings pause rather than restart dwell', () {
    expect(
      run([
        at(0, far, 15),
        at(40, centre, 40),
        at(55, centre, 250),
        at(75, centre, 45),
      ]),
      ['home'],
    );
  });

  test('long silence restarts dwell and pass-through does not notify', () {
    expect(
      run([at(0, far, 15), at(10, centre, 20), at(400, centre, 20)]),
      isEmpty,
    );
    expect(run([at(0, far, 15), at(10, centre, 20), at(25, far, 20)]), isEmpty);
  });

  test('each area notifies once', () {
    expect(
      run([
        at(0, far, 15),
        at(10, centre, 20),
        at(45, centre, 20),
        at(60, far, 15),
        at(70, centre, 20),
        at(110, centre, 20),
      ]),
      ['home'],
    );
  });
}
