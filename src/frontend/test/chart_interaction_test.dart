import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumpun_frontend/household_home.dart';
import 'package:rumpun_frontend/main.dart';

import 'fake_backend.dart';

/// The charts label only their busiest column, so touching one is how a week
/// is read precisely. These hold that gesture in place.
Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find
        .descendant(
          of: find.byType(FinanceScreen),
          matching: find.byType(Scrollable),
        )
        .last,
  );
  await tester.pumpAndSettle();
}

void main() {
  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RumpunApp(
        auth: fakeRepository(
          withStoredToken: true,
          accounts: [account(name: 'Tunai', balance: 9650000)],
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
              spent: 194500,
              netWorth: 9650000,
              complete: false,
            ),
          ],
          trendChangeBps: 484,
          trendSpendChangeBps: -6080,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keuangan'));
    await tester.pumpAndSettle();
  }

  testWidgets('holding a bar names that week and its amount', (tester) async {
    await pumpHome(tester);

    await reveal(tester, find.byType(SpendingChart));
    // At rest the caption reports the last finished week.
    expect(find.text('Minggu 17 Agu Rp 486.000'), findsOneWidget);
    final chart = tester.getRect(find.byType(SpendingChart));
    // The first of four slots, so the leftmost quarter of the chart.
    final gesture = await tester.startGesture(
      Offset(chart.left + chart.width * 0.12, chart.bottom - 40),
    );
    await tester.pump();
    expect(find.text('3 Agu: Rp 812.000'), findsOneWidget);

    // Dragging across moves the readout rather than needing a fresh tap.
    await gesture.moveTo(
      Offset(chart.left + chart.width * 0.38, chart.bottom - 40),
    );
    await tester.pump();
    expect(find.text('10 Agu: Rp 1.240.000'), findsOneWidget);

    // The unfinished week says so, so a short bar is not read as a real fall.
    await gesture.moveTo(
      Offset(chart.left + chart.width * 0.88, chart.bottom - 40),
    );
    await tester.pump();
    expect(find.text('24 Agu: Rp 194.500 (berjalan)'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    // Releasing returns the caption to its resting summary.
    expect(find.text('Minggu 17 Agu Rp 486.000'), findsOneWidget);
  });

  testWidgets('the net worth line reports the week under the finger', (
    tester,
  ) async {
    await pumpHome(tester);
    // The second chart sits below the fold on a 390x844 screen.
    await reveal(tester, find.byType(NetWorthChart));
    await tester.drag(find.byType(NetWorthChart), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(find.text('Sekarang Rp 9.650.000'), findsOneWidget);

    final chart = tester.getRect(find.byType(NetWorthChart));
    final gesture = await tester.startGesture(
      Offset(chart.left + chart.width * 0.12, chart.bottom - 30),
    );
    await tester.pump();
    expect(find.text('3 Agu: Rp 9.100.000'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Sekarang Rp 9.650.000'), findsOneWidget);
  });

  testWidgets('a vertical drag scrolls the page instead of scrubbing', (
    tester,
  ) async {
    await pumpHome(tester);
    await reveal(tester, find.byType(SpendingChart));
    final before = tester.getRect(find.byType(SpendingChart)).top;

    // The scrubber claims horizontal drags only. Claiming vertical ones would
    // trap the finger and make the home screen feel stuck.
    await tester.drag(find.byType(SpendingChart), const Offset(0, -160));
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byType(SpendingChart)).top, lessThan(before));
  });

  testWidgets('currency choice reloads charts on their own scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = fakeAuth(
      withStoredToken: true,
      accounts: [
        account(name: 'Tunai', balance: 9650000),
        account(name: 'SGD', balance: 50000, currency: 'SGD'),
      ],
      trendBuckets: [
        trendBucket(
          start: '2026-08-03',
          label: '3 Agu',
          spent: 1200,
          netWorth: 50000,
        ),
      ],
    );
    await tester.pumpWidget(RumpunApp(auth: fake.repository));
    await tester.pumpAndSettle();
    expect(fake.backend.lastTrendCurrency, isNull);
    await tester.tap(find.text('Keuangan'));
    await tester.pumpAndSettle();

    final sgd = find.byKey(const Key('trend-currency-SGD'));
    await reveal(tester, sgd);
    final before = tester.getRect(sgd).top;
    await tester.tap(sgd);
    await tester.pumpAndSettle();

    expect(fake.backend.lastTrendCurrency, 'SGD');
    expect(tester.getRect(sgd).top, closeTo(before, 1));
    expect(find.textContaining('SGD '), findsWidgets);
  });
}
