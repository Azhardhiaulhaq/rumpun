import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumpun_frontend/main.dart';

import 'fake_backend.dart';

void main() {
  final auth = fakeRepository(withStoredToken: true);
  for (final entry in <String, Widget>{
    'home': Scaffold(body: HomeScreen(auth: auth)),
    'review': Scaffold(body: ReviewScreen(auth: auth)),
    'shell': AppShell(auth: auth),
  }.entries) {
    testWidgets('narrow ${entry.key}', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'NotoSans'),
          home: entry.value,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
