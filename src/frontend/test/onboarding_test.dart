import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumpun_frontend/main.dart';

import 'fake_backend.dart';

void phone(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<FakeAuth> signIn(
  WidgetTester tester, {
  bool withHousehold = false,
  int invites = 0,
  String? failSetupWithCode,
}) async {
  final fake = fakeAuth(
    isNewUser: true,
    withHousehold: withHousehold,
    invites: invites,
    failSetupWithCode: failSetupWithCode,
  );
  await tester.pumpWidget(RumpunApp(auth: fake.repository));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Masuk dengan Google'));
  await tester.tap(find.text('Masuk dengan Google'));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  group('a user who belongs nowhere', () {
    testWidgets('is asked to create or join, not dropped into a ledger',
        (tester) async {
      phone(tester);
      await signIn(tester);

      expect(find.text('Buat rumah tangga baru'), findsOneWidget);
      expect(find.text('Total dana keluarga'), findsNothing,
          reason: 'landing in an empty ledger would hide the invite path');
    });

    testWidgets('creating a household opens the ledger', (tester) async {
      phone(tester);
      final fake = await signIn(tester);

      await tester.tap(find.text('Buat rumah tangga baru'));
      await tester.pumpAndSettle();
      expect(find.text('Rumah tangga baru'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, namedHousehold);
      await tester.tap(find.text('Buka catatan rumah'));
      await tester.pumpAndSettle();

      expect(fake.backend.lastSetupBody?['name'], namedHousehold);
      expect(find.text('Total dana keluarga'), findsOneWidget);
      expect(find.text(namedHousehold), findsOneWidget);
    });

    testWidgets('closing the app before choosing returns to the choice',
        (tester) async {
      phone(tester);
      await tester.pumpWidget(RumpunApp(
        auth: fakeRepository(withStoredToken: true, withHousehold: false),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Buat rumah tangga baru'), findsOneWidget);
      expect(find.text('Total dana keluarga'), findsNothing);
    });
  });

  group('invitations', () {
    testWidgets('an invited user sees who invited them and to what',
        (tester) async {
      phone(tester);
      await signIn(tester, invites: 1);

      expect(find.text(invitingHousehold), findsOneWidget);
      expect(find.text('Budi mengundangmu sebagai Anggota.'), findsOneWidget,
          reason: 'who invited you, and as what, in plain words');
    });

    testWidgets('accepting joins that household and opens its ledger',
        (tester) async {
      phone(tester);
      final fake = await signIn(tester, invites: 1);

      await tester.tap(find.textContaining('Gabung'));
      await tester.pumpAndSettle();

      expect(fake.backend.acceptedInviteId, inviteId);
      expect(find.text('Total dana keluarga'), findsOneWidget);
      expect(find.text(invitingHousehold), findsOneWidget);
      expect(fake.repository.session?.household?.role, 'member');
    });

    testWidgets('declining leaves the user free to start their own',
        (tester) async {
      phone(tester);
      final fake = await signIn(tester, invites: 1);

      await tester.tap(find.text('Tolak undangan'));
      await tester.pumpAndSettle();

      expect(fake.backend.declinedInviteId, inviteId);
      expect(find.text(invitingHousehold), findsNothing);
      expect(find.text('Buat rumah tangga baru'), findsOneWidget,
          reason: 'the only remaining path becomes the primary action');
    });

    testWidgets('an invitation that was already answered explains itself',
        (tester) async {
      phone(tester);
      await signIn(
        tester,
        invites: 1,
        failSetupWithCode: 'invite_already_resolved',
      );

      await tester.tap(find.textContaining('Gabung'));
      await tester.pumpAndSettle();

      expect(find.text('Undangan ini sudah tidak berlaku.'), findsOneWidget);
      expect(find.text('Total dana keluarga'), findsNothing);
    });

    testWidgets('a second tap cannot answer the same invite twice',
        (tester) async {
      phone(tester);
      final fake = await signIn(tester, invites: 1);
      fake.backend.latency = const Duration(milliseconds: 300);

      await tester.tap(find.textContaining('Gabung'));
      await tester.pump(const Duration(milliseconds: 50));

      // While the first request is in flight, neither answer is tappable.
      expect(find.textContaining('Gabung'), findsNothing,
          reason: 'the accept label is replaced by a spinner');
      final decline = tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Tolak undangan'));
      expect(decline.enabled, isFalse,
          reason: 'declining mid-accept would race the server');

      await tester.pumpAndSettle();
      expect(fake.backend.acceptCalls, 1);
      expect(find.text('Total dana keluarga'), findsOneWidget);
    });
  });

  group('managing people', () {
    Future<FakeAuth> openPeople(
      WidgetTester tester, {
      List<Map<String, dynamic>> members = const [],
      List<Map<String, dynamic>> openInvites = const [],
      String? failInviteWithCode,
    }) async {
      final fake = fakeAuth(
        withStoredToken: true,
        members: members,
        openInvites: openInvites,
        failInviteWithCode: failInviteWithCode,
      );
      await tester.pumpWidget(RumpunApp(auth: fake.repository));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Buka profil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anggota rumah'));
      await tester.pumpAndSettle();
      return fake;
    }

    testWidgets('shows members and marks which one is you', (tester) async {
      phone(tester);
      await openPeople(tester, members: [
        member(name: 'Budi', email: 'budi@rumpun.app', role: 'owner', isYou: true),
        member(name: 'Siti', email: 'siti@rumpun.app'),
      ]);

      expect(find.text('Budi (kamu)'), findsOneWidget);
      expect(find.text('Siti'), findsOneWidget);
      expect(find.text('Pemilik rumah'), findsOneWidget);
    });

    testWidgets('sends an invite with the chosen role', (tester) async {
      phone(tester);
      final fake = await openPeople(tester, members: [
        member(name: 'Budi', email: 'budi@rumpun.app', role: 'owner', isYou: true),
      ]);

      await tester.tap(find.text('Undang lewat email'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'siti@rumpun.app');
      await tester.tap(find.text('Kirim undangan'));
      await tester.pumpAndSettle();

      expect(fake.backend.lastInviteBody?['email'], 'siti@rumpun.app');
      expect(fake.backend.lastInviteBody?['role'], 'member');
    });

    testWidgets('a rejected invite keeps the sheet open with the reason',
        (tester) async {
      phone(tester);
      await openPeople(
        tester,
        members: [
          member(name: 'Budi', email: 'b@rumpun.app', role: 'owner', isYou: true)
        ],
        failInviteWithCode: 'already_a_member',
      );

      await tester.tap(find.text('Undang lewat email'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'siti@rumpun.app');
      await tester.tap(find.text('Kirim undangan'));
      await tester.pumpAndSettle();

      expect(find.text('Orang itu sudah ada di rumah ini.'), findsOneWidget);
      expect(find.text('Kirim undangan'), findsOneWidget);
    });

    testWidgets('an invalid email never reaches the server', (tester) async {
      phone(tester);
      final fake = await openPeople(tester, members: [
        member(name: 'Budi', email: 'b@rumpun.app', role: 'owner', isYou: true)
      ]);

      await tester.tap(find.text('Undang lewat email'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'bukan-email');
      await tester.tap(find.text('Kirim undangan'));
      await tester.pump();

      expect(find.text('Masukkan alamat email yang valid.'), findsOneWidget);
      expect(fake.backend.lastInviteBody, isNull);
    });

    testWidgets('an open invite can be withdrawn', (tester) async {
      phone(tester);
      final fake = await openPeople(
        tester,
        members: [
          member(name: 'Budi', email: 'b@rumpun.app', role: 'owner', isYou: true)
        ],
        openInvites: [openInvite(email: 'siti@rumpun.app')],
      );

      expect(find.text('siti@rumpun.app'), findsOneWidget);
      await tester.tap(find.byTooltip('Tarik undangan'));
      await tester.pumpAndSettle();

      expect(fake.backend.revokedInviteId, inviteId);
    });

    testWidgets('the roster fits the narrowest supported phone',
        (tester) async {
      phone(tester, size: const Size(320, 568));
      await openPeople(tester, members: [
        member(
          name: 'Nama Yang Sangat Panjang Sekali Untuk Diuji',
          email: 'alamat.email.yang.panjang.sekali@contoh-rumpun.app',
          role: 'owner',
          isYou: true,
        ),
      ]);

      expect(tester.takeException(), isNull);
    });
  });
}
