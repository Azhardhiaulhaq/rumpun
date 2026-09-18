import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumpun_frontend/main.dart';

void main() {
  for (final entry in <String, Widget>{
    'home': const Scaffold(body: HomeScreen()),
    'review': const Scaffold(body: ReviewScreen()),
    'shell': const AppShell(),
  }.entries) {
    testWidgets('narrow ${entry.key}', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'NotoSans'),
        home: entry.value,
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
