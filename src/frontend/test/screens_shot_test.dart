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
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('golden/splash_mid.png'));
    await tester.pumpAndSettle();
  });

  testWidgets('login at rest', (tester) async {
    _view(tester, const Size(390, 844));
    await tester.pumpWidget(RumpunApp(auth: fakeRepository()));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('golden/login.png'));
  });

  testWidgets('login error on the narrowest phone', (tester) async {
    // The error note is the tallest the screen ever gets, so this is the
    // layout worth checking at 320px.
    _view(tester, const Size(320, 568));
    await tester.pumpWidget(
        RumpunApp(auth: fakeRepository(failWithCode: 'invalid_google_token')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Masuk dengan Google'));
    await tester.pumpAndSettle();

    expect(find.byType(AuthErrorNote), findsOneWidget);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('golden/login_error_320.png'));
  });

  testWidgets('ledger with data', (tester) async {
    _view(tester, const Size(390, 844));
    await tester.pumpWidget(RumpunApp(
      auth: fakeRepository(
        withStoredToken: true,
        accounts: [
          account(name: 'Tunai', balance: 1250000),
          account(name: 'Bank', balance: 8400000),
        ],
        recent: [
          ledgerEntry(description: 'Belanja rumah', amount: 286500),
          ledgerEntry(description: 'Gaji bulanan', amount: 4000000, type: 'income'),
          ledgerEntry(description: 'Makan bersama', amount: 94000),
        ],
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('golden/ledger.png'));
  });

  testWidgets('review inbox', (tester) async {
    _view(tester, const Size(390, 844));
    await tester.pumpWidget(RumpunApp(
      auth: fakeRepository(
        withStoredToken: true,
        candidates: [
          candidateJson(description: 'Toko kebutuhan rumah', amount: 286500),
          candidateJson(description: 'Pembayaran layanan', amount: null,
              state: 'needs_input'),
        ],
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tinjau'));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('golden/review.png'));
  });
}
