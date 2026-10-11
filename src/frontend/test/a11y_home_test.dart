import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumpun_frontend/main.dart';

import 'fake_backend.dart';

/// The home screen carries the only numbers in the app, so it has to hold up
/// for contrast, screen readers, tap targets, and a keyboard.
void main() {
  Future<void> pumpHome(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RumpunApp(
        auth: fakeRepository(
          withStoredToken: true,
          accounts: [
            account(name: 'Dompet dapur', balance: 1250000),
            account(name: 'BCA', balance: 8400000, kind: 'bank'),
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
              netWorth: 9650000,
            ),
            trendBucket(
              start: '2026-08-24',
              label: '24 Agu',
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
    final shell = tester.widget<AppShell>(find.byType(AppShell));
    Navigator.of(tester.element(find.byType(AppShell))).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(body: HomeScreen(auth: shell.auth)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('home meets the accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpHome(tester);

    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('the balance card is reachable and operable by keyboard', (
    tester,
  ) async {
    await pumpHome(tester);
    Focus.of(tester.element(find.text('Total aset keluarga'))).requestFocus();
    await tester.pumpAndSettle();

    // Tab has to reach the card, and Enter has to open it: a card that only
    // answers to a tap is unusable with a keyboard or a switch device.
    expect(find.text('Dompet dapur'), findsNothing);

    var guard = 0;
    while (find.text('Dompet dapur').evaluate().isEmpty && guard++ < 24) {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      if (find.text('Dompet dapur').evaluate().isNotEmpty) break;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    expect(
      find.text('Dompet dapur'),
      findsOneWidget,
      reason: 'the breakdown opens without a pointer',
    );
  });

  testWidgets('the charts describe themselves to a screen reader', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpHome(tester);

    // A bar is a rectangle to a screen reader unless it says what it is, so
    // each one carries its week and its amount.
    expect(
      find.bySemanticsLabel(RegExp(r'3 Agu: Rp 812\.000')),
      findsOneWidget,
    );
    // The running week says so, rather than reading as a collapse in spending.
    expect(find.bySemanticsLabel(RegExp('minggu berjalan')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Grafik total aset')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the home screen holds up on the narrowest phone', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(320, 568));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Total aset keluarga'));
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'the breakdown must not overflow a 320px screen',
    );
  });
}
