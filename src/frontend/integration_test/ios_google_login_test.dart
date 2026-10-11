import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rumpun_frontend/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Google login on the connected iPhone', (tester) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 1));
    final login = find.text('Masuk dengan Google');
    if (login.evaluate().isNotEmpty) {
      await tester.ensureVisible(login);
      await tester.tap(login);
      for (var attempt = 0; attempt < 120; attempt++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.text('Rumah kita').evaluate().isNotEmpty) break;
        final errors = find.byType(app.AuthErrorNote);
        if (errors.evaluate().isNotEmpty) {
          final note = tester.widget<app.AuthErrorNote>(errors.first);
          fail('Live Google sign-in failed: ${note.message}');
        }
      }
    }
    expect(find.text('Rumah kita'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
