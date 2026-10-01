import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumpun_frontend/main.dart';

import 'fake_backend.dart';

void _view(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('splash mid-animation', (tester) async {
    _view(tester, const Size(390, 844));
    await tester.pumpWidget(RumpunApp(auth: fakeRepository()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 620));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/splash_mid.png'),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('login at rest', (tester) async {
    _view(tester, const Size(390, 844));
    await tester.pumpWidget(RumpunApp(auth: fakeRepository()));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/login.png'),
    );
  });

  testWidgets('login error on the narrowest phone', (tester) async {
    // The error note is the tallest the screen ever gets, so this is the
    // layout worth checking at 320px.
    _view(tester, const Size(320, 568));
    await tester.pumpWidget(
      RumpunApp(auth: fakeRepository(failWithCode: 'invalid_google_token')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Masuk dengan Google'));
    await tester.pumpAndSettle();

    expect(find.byType(AuthErrorNote), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/login_error_320.png'),
    );
  });

  testWidgets('ledger with data', (tester) async {
    _view(tester, const Size(390, 844));
    await tester.pumpWidget(
      RumpunApp(
        auth: fakeRepository(
          withStoredToken: true,
          accounts: [
            account(name: 'Tunai', balance: 1250000),
            account(name: 'Bank', balance: 8400000, kind: 'bank'),
          ],
          trendBuckets: [
            trendBucket(
              start: '2026-08-03',
              label: '3 Agu',
              spent: 812000,
              netWorth: 9100000,
            ),
            trendBucket(
              start: '2026-08-10',
              label: '10 Agu',
              spent: 1240000,
              netWorth: 9860000,
            ),
            trendBucket(
              start: '2026-08-17',
              label: '17 Agu',
              spent: 486000,
              netWorth: 9374000,
            ),
            trendBucket(
              start: '2026-08-24',
              label: '24 Agu',
              spent: 934500,
              netWorth: 9650000,
            ),
            trendBucket(
              start: '2026-08-31',
              label: '31 Agu',
              spent: 1105000,
              netWorth: 9204000,
            ),
            trendBucket(
              start: '2026-09-07',
              label: '7 Sep',
              spent: 623000,
              netWorth: 9650000,
            ),
            trendBucket(
              start: '2026-09-14',
              label: '14 Sep',
              spent: 194500,
              netWorth: 9650000,
              complete: false,
            ),
          ],
          trendChangeBps: 484,
          trendSpendChangeBps: -4365,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/ledger.png'),
    );
  });

  testWidgets('review inbox', (tester) async {
    _view(tester, const Size(390, 844));
    await tester.pumpWidget(
      RumpunApp(
        auth: fakeRepository(
          withStoredToken: true,
          candidates: [
            candidateJson(description: 'Toko kebutuhan rumah', amount: 286500),
            candidateJson(
              description: 'Pembayaran layanan',
              amount: null,
              state: 'needs_input',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tinjau'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/review.png'),
    );
  });

  testWidgets('Gmail connection on a narrow phone', (tester) async {
    _view(tester, const Size(320, 568));
    await tester.pumpWidget(
      RumpunApp(auth: fakeRepository(withStoredToken: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Buka profil'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Hubungkan Gmail'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Hubungkan Gmail'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/gmail_connect_320.png'),
    );
  });
}
