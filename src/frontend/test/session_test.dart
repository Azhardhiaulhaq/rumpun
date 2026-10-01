import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumpun_frontend/api/models.dart';
import 'package:rumpun_frontend/main.dart';

import 'fake_backend.dart';

/// The access token lives 15 minutes and the refresh token 30 days, so any app
/// left open past lunch meets a 401 before the user does anything wrong.
/// These cover what happens next.
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('an expired access token is renewed without asking for a login', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = fakeAuth(
      withStoredToken: true,
      accounts: [account(name: 'Tunai', balance: 1250000)],
    );
    await tester.pumpWidget(RumpunApp(auth: fake.repository));
    await tester.pumpAndSettle();
    expect(find.text('Rp 1.250.000'), findsOneWidget);

    // The phone has been in a pocket long enough for the access token to die.
    final refreshesSoFar = fake.backend.refreshCalls;
    fake.backend.accessTokenExpired = true;

    await tester.drag(find.byType(ListView), const Offset(0, 320));
    await tester.pumpAndSettle();

    expect(
      fake.backend.expiredCalls,
      greaterThan(0),
      reason: 'the stale token really was rejected',
    );
    expect(fake.backend.refreshCalls, greaterThan(refreshesSoFar));
    // The point of the whole exercise: the household never saw a login screen.
    expect(find.text('Masuk dengan Google'), findsNothing);
    expect(find.text('Rp 1.250.000'), findsOneWidget);
  });

  test('one refresh covers every call that raced the same expiry', () async {
    final fake = fakeAuth(withStoredToken: true);
    await fake.repository.restore();
    final refreshesSoFar = fake.backend.refreshCalls;
    fake.backend.accessTokenExpired = true;

    // The home screen asks for the dashboard, the charts, and the accounts at
    // once. Refresh tokens rotate and the server revokes a family when one is
    // replayed, so three independent refreshes would sign the household out.
    await Future.wait([
      fake.repository.dashboard(),
      fake.repository.trends(),
      fake.repository.accounts(),
    ]);

    expect(fake.backend.refreshCalls, refreshesSoFar + 1);
  });

  test('a dead refresh token ends the session instead of looping', () async {
    final fake = fakeAuth(withStoredToken: true);
    await fake.repository.restore();
    fake.backend.accessTokenExpired = true;
    fake.backend.refreshTokenRejected = true;

    await expectLater(
      fake.repository.dashboard(),
      throwsA(isA<ApiException>()),
    );
    // Signed out locally, so the app routes to sign-in rather than retrying a
    // token the server has already refused.
    expect(fake.repository.isSignedIn, isFalse);
  });

  test('being offline does not sign the household out', () async {
    final fake = fakeAuth(withStoredToken: true);
    await fake.repository.restore();
    expect(fake.repository.isSignedIn, isTrue);

    fake.backend.accessTokenExpired = true;
    fake.backend.offline = true;

    // A tunnel is not a revoked session. The call fails, but discarding the
    // refresh token here would mean every lost signal costs a Google sign-in.
    await expectLater(
      fake.repository.dashboard(),
      throwsA(isA<NetworkException>()),
    );
    expect(fake.repository.isSignedIn, isTrue);

    // Back in signal, the same session recovers on its own.
    fake.backend.offline = false;
    await fake.repository.dashboard();
    expect(fake.repository.isSignedIn, isTrue);
  });
}
