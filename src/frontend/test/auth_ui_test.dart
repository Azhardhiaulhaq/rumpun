import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumpun_frontend/main.dart';

import 'fake_backend.dart';

/// Guards the states that only appear while the network is slow or failing,
/// at the narrowest phone width the project supports.
void main() {
  void phone(WidgetTester tester, {Size size = const Size(320, 568)}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('the sign-in button locks while Google is open', (tester) async {
    phone(tester);
    await tester.pumpWidget(RumpunApp(auth: fakeRepository()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Masuk dengan Google'));
    await tester.tap(find.text('Masuk dengan Google'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).first).enabled,
      isFalse,
      reason: 'a second tap would open a duplicate session',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('an unreachable server explains itself instead of hanging', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      RumpunApp(auth: fakeRepository(failWithCode: 'service_unavailable')),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Masuk dengan Google'));
    await tester.tap(find.text('Masuk dengan Google'));
    await tester.pumpAndSettle();

    expect(find.byType(AuthErrorNote), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the error note stays inside a narrow phone', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      RumpunApp(auth: fakeRepository(failWithCode: 'invalid_google_token')),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Masuk dengan Google'));
    await tester.tap(find.text('Masuk dengan Google'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final note = tester.getRect(find.byType(AuthErrorNote));
    expect(note.left, greaterThanOrEqualTo(0));
    expect(note.right, lessThanOrEqualTo(320));
  });

  testWidgets('the sign-in screen fits the narrowest supported phone', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(RumpunApp(auth: fakeRepository()));
    await tester.pump();
    expect(
      tester.takeException(),
      isNull,
      reason: 'splash must not overflow before the session resolves',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the household setup form fits a narrow phone', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      RumpunApp(
        auth: fakeRepository(withStoredToken: true, householdNamed: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nama rumah tangga'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every auth control is reachable by keyboard', (tester) async {
    phone(tester, size: const Size(390, 844));
    await tester.pumpWidget(
      RumpunApp(
        auth: fakeRepository(withStoredToken: true, householdNamed: false),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextFormField).first);
    await tester.pump();

    var reached = 0;
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      if (FocusManager.instance.primaryFocus?.context != null) reached++;
    }
    expect(reached, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
