@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rumpun_frontend/api/api_client.dart';
import 'package:rumpun_frontend/api/models.dart';

/// Exercises the real backend over real HTTP. Excluded from `flutter test` by
/// the `live` tag because it needs `docker compose up` in src/backend.
///
///   flutter test test_live --tags live
///
/// Point it at a tunnel to check what the phone will actually talk to:
///
///   flutter test test_live --tags live \
///     --dart-define=RUMPUN_API_BASE_URL=https://example.ngrok-free.dev/api/v1
void main() {
  const baseUrl = String.fromEnvironment(
    'RUMPUN_API_BASE_URL',
    defaultValue: 'http://localhost:8000/api/v1',
  );
  final client = ApiClient(baseUrl: baseUrl);
  final email = 'live-${DateTime.now().microsecondsSinceEpoch}@rumpun.app';
  const password = 'kata-sandi-panjang-sekali';

  test('register creates a household and returns a usable session', () async {
    final session = await client.register(
      email: email,
      password: password,
      displayName: 'Uji Langsung',
    );
    expect(session.accessToken, isNotEmpty);
    expect(session.user.email, email);
    expect(session.household, isNull);
    expect(session.isNewUser, isTrue);
  });

  test('registering without a household name leaves the user in onboarding',
      () async {
    final fresh = 'setup-${DateTime.now().microsecondsSinceEpoch}@rumpun.app';
    final session = await client.register(
      email: fresh,
      password: password,
      displayName: 'Perlu Setup',
    );

    expect(session.household, isNull,
        reason: 'auto-creating one would strand an invited member');
    expect(session.needsOnboarding, isTrue);

    final created = await client.createHousehold(
      accessToken: session.accessToken,
      name: 'Keluarga Uji',
      baseCurrency: 'IDR',
    );
    expect(created.name, 'Keluarga Uji');
    expect(created.role, 'owner');

    final next = await client.login(email: fresh, password: password);
    expect(next.needsOnboarding, isFalse);
    expect(next.household?.name, 'Keluarga Uji');
    expect(next.isNewUser, isFalse);
  });

  test('the setup form rejects a currency the ledger cannot post', () async {
    final session = await client.login(email: email, password: password);
    await client.createHousehold(
      accessToken: session.accessToken,
      name: 'Rumah Uji',
      baseCurrency: 'IDR',
    );
    await expectLater(
      client.updateHousehold(
        accessToken: session.accessToken,
        name: 'Rumah Uji',
        baseCurrency: 'ZZZ',
      ),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'unsupported_currency')),
    );
  });

  test('household setup refuses an unauthenticated caller', () async {
    await expectLater(
      client.updateHousehold(
        accessToken: 'not-a-real-token',
        name: 'Rumah Uji',
        baseCurrency: 'IDR',
      ),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'status', 401)),
    );
  });

  test('login returns the same user', () async {
    final session = await client.login(email: email, password: password);
    expect(session.user.email, email);
  });

  test('wrong password surfaces invalid_credentials', () async {
    await expectLater(
      client.login(email: email, password: 'jelas-salah-sekali'),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'invalid_credentials')
          .having((e) => e.statusCode, 'status', 401)),
    );
  });

  test('duplicate email surfaces email_already_registered', () async {
    await expectLater(
      client.register(
        email: email,
        password: password,
        displayName: 'Kembar',
      ),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'email_already_registered')),
    );
  });

  test('refresh rotates the token and reuse is rejected', () async {
    final first = await client.login(email: email, password: password);
    final second = await client.refresh(first.refreshToken);
    expect(second.refreshToken, isNot(first.refreshToken));

    await expectLater(
      client.refresh(first.refreshToken),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'refresh_token_reused')),
    );
  });

  test('logout invalidates the refresh token', () async {
    final session = await client.login(email: email, password: password);
    await client.logout(session.refreshToken);
    await expectLater(
      client.refresh(session.refreshToken),
      throwsA(isA<ApiException>()),
    );
  });

  test('a bogus Google token is rejected, not silently accepted', () async {
    await expectLater(
      client.loginWithGoogle('bukan-token-google'),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'invalid_google_token')),
    );
  });

  test('an unreachable server raises NetworkException', () async {
    final offline = ApiClient(baseUrl: 'http://127.0.0.1:9/api/v1');
    await expectLater(
      offline.login(email: email, password: password),
      throwsA(isA<NetworkException>()),
    );
  });

  test('an invited member joins the inviter household, not a new one', () async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final ownerEmail = 'own-$stamp@rumpun.app';
    final memberEmail = 'mem-$stamp@rumpun.app';

    final owner = await client.register(
      email: ownerEmail,
      password: password,
      displayName: 'Budi',
    );
    expect(owner.household, isNull);

    final household = await client.createHousehold(
      accessToken: owner.accessToken,
      name: 'Keluarga Budi',
      baseCurrency: 'IDR',
    );

    await client.invite(
      accessToken: owner.accessToken,
      email: memberEmail,
      role: 'member',
    );

    final member = await client.register(
      email: memberEmail,
      password: password,
      displayName: 'Siti',
    );
    expect(member.household, isNull);
    expect(member.pendingInvites, hasLength(1));
    expect(member.pendingInvites.first.householdName, 'Keluarga Budi');
    expect(member.pendingInvites.first.invitedByName, 'Budi');

    final joined = await client.acceptInvite(
      accessToken: member.accessToken,
      inviteId: member.pendingInvites.first.id,
    );
    expect(joined.id, household.id, reason: 'the same ledger, not a new one');
    expect(joined.role, 'member');

    final people = await client.people(owner.accessToken);
    expect(people.members, hasLength(2));
    expect(people.invites, isEmpty);

    final next = await client.login(email: memberEmail, password: password);
    expect(next.household?.id, household.id);
    expect(next.needsOnboarding, isFalse);
  });

  test('an invite cannot be accepted by a different address', () async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final owner = await client.register(
      email: 'own2-$stamp@rumpun.app',
      password: password,
      displayName: 'Budi',
    );
    await client.createHousehold(
      accessToken: owner.accessToken,
      name: 'Keluarga Budi',
      baseCurrency: 'IDR',
    );
    await client.invite(
      accessToken: owner.accessToken,
      email: 'invited-$stamp@rumpun.app',
      role: 'member',
    );
    final people = await client.people(owner.accessToken);

    final stranger = await client.register(
      email: 'stranger-$stamp@rumpun.app',
      password: password,
      displayName: 'Rina',
    );
    expect(stranger.pendingInvites, isEmpty);

    await expectLater(
      client.acceptInvite(
        accessToken: stranger.accessToken,
        inviteId: people.invites.first.id,
      ),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'invite_not_found')),
    );
  });

  test('a plain member cannot invite anyone', () async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final owner = await client.register(
      email: 'own3-$stamp@rumpun.app',
      password: password,
      displayName: 'Budi',
    );
    await client.createHousehold(
      accessToken: owner.accessToken,
      name: 'Keluarga Budi',
      baseCurrency: 'IDR',
    );
    final memberEmail = 'mem3-$stamp@rumpun.app';
    await client.invite(
      accessToken: owner.accessToken,
      email: memberEmail,
      role: 'member',
    );
    final member = await client.register(
      email: memberEmail,
      password: password,
      displayName: 'Siti',
    );
    await client.acceptInvite(
      accessToken: member.accessToken,
      inviteId: member.pendingInvites.first.id,
    );

    final asMember = await client.login(email: memberEmail, password: password);
    await expectLater(
      client.invite(
        accessToken: asMember.accessToken,
        email: 'nobody-$stamp@rumpun.app',
        role: 'member',
      ),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'household_edit_denied')),
    );
  });
}
