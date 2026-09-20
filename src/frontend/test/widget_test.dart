import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumpun_frontend/api/auth_repository.dart';
import 'package:rumpun_frontend/main.dart';

import 'fake_backend.dart';

void phone(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The splash resolves the stored session first, so pumpAndSettle lands on
/// whichever screen that session dictates.
Future<void> start(WidgetTester tester, {AuthRepository? auth}) async {
  await tester.pumpWidget(RumpunApp(auth: auth ?? fakeRepository()));
  await tester.pumpAndSettle();
}

Future<void> tapGoogle(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Masuk dengan Google'));
  await tester.tap(find.text('Masuk dengan Google'));
  await tester.pumpAndSettle();
}

Future<void> openHome(WidgetTester tester) async {
  await start(tester, auth: fakeRepository(withStoredToken: true));
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('sign in', () {
    testWidgets('offers Google as the only way in', (tester) async {
      phone(tester);
      await start(tester);

      expect(find.text('Masuk dengan Google'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing,
          reason: 'there is no email or password form any more');
      expect(find.text('Buat akun keluarga'), findsNothing);
    });

    testWidgets('a returning member lands straight on the ledger',
        (tester) async {
      phone(tester);
      final fake = fakeAuth();
      await start(tester, auth: fake.repository);
      await tapGoogle(tester);

      expect(fake.google.initialized, isTrue);
      expect(fake.google.authenticateCalls, 1);
      expect(find.text('Total dana keluarga'), findsOneWidget);
      expect(find.text('Halo, $signedInName'), findsOneWidget);
    });

    testWidgets('a first-time member is asked to name the household',
        (tester) async {
      phone(tester);
      await start(
        tester,
        auth: fakeRepository(isNewUser: true, householdNamed: false),
      );
      await tapGoogle(tester);

      expect(find.text('Halo, $signedInName'), findsOneWidget);
      expect(find.text('Nama rumah tangga'), findsOneWidget);
      expect(find.text('Total dana keluarga'), findsNothing);
    });

    testWidgets('dismissing the Google picker leaves the screen untouched',
        (tester) async {
      phone(tester);
      await start(tester, auth: fakeRepository(googleError: canceledPicker()));
      await tapGoogle(tester);

      expect(find.text('Masuk dengan Google'), findsOneWidget);
      expect(find.byType(AuthErrorNote), findsNothing,
          reason: 'cancelling is a choice, not an error');
    });

    testWidgets('a server rejection is explained and the button comes back',
        (tester) async {
      phone(tester);
      await start(
        tester,
        auth: fakeRepository(failWithCode: 'invalid_google_token'),
      );
      await tapGoogle(tester);

      expect(find.text('Server menolak identitas Google ini. Coba masuk lagi.'),
          findsOneWidget);
      expect(find.text('Masuk dengan Google'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).first).enabled,
        isTrue,
      );
    });

    testWidgets('a build without a client ID says so instead of hiding',
        (tester) async {
      phone(tester);
      await start(tester, auth: fakeRepository(googleConfigured: false));

      expect(find.text('Masuk dengan Google'), findsNothing);
      expect(find.byType(AuthErrorNote), findsOneWidget);
      expect(find.textContaining('Google client ID'), findsOneWidget);
    });
  });

  group('household setup', () {
    Future<FakeAuth> openSetup(WidgetTester tester, {String? failCode}) async {
      final fake = fakeAuth(
        isNewUser: true,
        householdNamed: false,
        failSetupWithCode: failCode,
      );
      await start(tester, auth: fake.repository);
      await tapGoogle(tester);
      return fake;
    }

    testWidgets('rejects a blank name before calling the server',
        (tester) async {
      phone(tester);
      final fake = await openSetup(tester);

      await tester.enterText(find.byType(TextFormField).first, '   ');
      await tester.tap(find.text('Buka catatan rumah'));
      await tester.pump();

      expect(find.text('Beri nama rumah tanggamu.'), findsOneWidget);
      expect(fake.backend.lastSetupBody, isNull);
    });

    testWidgets('sends the name and currency, then opens the ledger',
        (tester) async {
      phone(tester);
      final fake = await openSetup(tester);

      await tester.enterText(find.byType(TextFormField).first, namedHousehold);
      await tester.tap(find.text('Buka catatan rumah'));
      await tester.pumpAndSettle();

      expect(fake.backend.lastSetupBody?['name'], namedHousehold);
      expect(fake.backend.lastSetupBody?['base_currency'], 'IDR');
      expect(find.text('Total dana keluarga'), findsOneWidget);
      expect(find.text(namedHousehold), findsOneWidget);
    });

    testWidgets('a rejected setup keeps the form and its values',
        (tester) async {
      phone(tester);
      await openSetup(tester, failCode: 'unsupported_currency');

      await tester.enterText(find.byType(TextFormField).first, namedHousehold);
      await tester.tap(find.text('Buka catatan rumah'));
      await tester.pumpAndSettle();

      expect(find.text('Mata uang itu belum didukung.'), findsOneWidget);
      expect(find.text('Buka catatan rumah'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        namedHousehold,
        reason: 'retyping the name after a server error is busywork',
      );
    });

    testWidgets('the currency picker offers the currencies the API accepts',
        (tester) async {
      phone(tester);
      await openSetup(tester);

      await tester.tap(find.text('IDR, Rupiah'));
      await tester.pumpAndSettle();

      expect(find.text('SGD, Dolar Singapura'), findsWidgets);
      expect(find.text('USD, Dolar AS'), findsWidgets);
    });
  });

  group('session', () {
    testWidgets('a stored session skips sign-in', (tester) async {
      phone(tester);
      await openHome(tester);

      expect(find.text('Total dana keluarga'), findsOneWidget);
      expect(find.text('Masuk dengan Google'), findsNothing);
    });

    testWidgets('closing the app mid-setup returns to setup', (tester) async {
      phone(tester);
      await start(
        tester,
        auth: fakeRepository(withStoredToken: true, householdNamed: false),
      );

      expect(find.text('Nama rumah tangga'), findsOneWidget);
      expect(find.text('Total dana keluarga'), findsNothing);
    });

    testWidgets('signing out clears the session and Google', (tester) async {
      phone(tester);
      final fake = fakeAuth();
      await start(tester, auth: fake.repository);
      await tapGoogle(tester);

      await tester.tap(find.byTooltip('Buka profil'));
      await tester.pumpAndSettle();
      expect(find.text(signedInEmail), findsOneWidget);

      await tester.tap(find.text('Keluar dari akun'));
      await tester.pumpAndSettle();

      expect(find.text('Masuk dengan Google'), findsOneWidget);
      expect(fake.google.signOutCalls, 1);
      expect(fake.repository.isSignedIn, isFalse);
    });
  });

  group('the ledger', () {
    testWidgets('shows the household total and its entries', (tester) async {
      phone(tester);
      await start(
        tester,
        auth: fakeRepository(
          withStoredToken: true,
          accounts: [account(name: 'Tunai', balance: 1250000)],
          recent: [
            ledgerEntry(description: 'Belanja rumah', amount: 286500),
            ledgerEntry(
                description: 'Gaji', amount: 4000000, type: 'income'),
          ],
        ),
      );

      expect(find.text('Rp 1.250.000'), findsOneWidget);
      expect(find.text('1 akun tercatat'), findsOneWidget);
      expect(find.text('Belanja rumah'), findsOneWidget);
      expect(find.text('−Rp 286.500'), findsOneWidget);
      expect(find.text('+Rp 4.000.000'), findsOneWidget,
          reason: 'income is signed so it reads differently from a spend');
    });

    testWidgets('hides the balance on request', (tester) async {
      phone(tester);
      await start(
        tester,
        auth: fakeRepository(
          withStoredToken: true,
          accounts: [account(name: 'Tunai', balance: 1250000)],
        ),
      );

      await tester.tap(find.byTooltip('Sembunyikan saldo'));
      await tester.pump();
      expect(find.text('Rp 1.250.000'), findsNothing);
      expect(find.textContaining('•'), findsOneWidget);
    });

    testWidgets('an empty ledger says so without claiming a failure',
        (tester) async {
      phone(tester);
      await start(tester, auth: fakeRepository(withStoredToken: true));

      expect(find.text('Rp 0'), findsOneWidget);
      expect(find.text('Belum ada akun'), findsOneWidget);
      expect(find.text('Belum ada catatan'), findsOneWidget);
    });

    testWidgets('a failed load offers a retry that works', (tester) async {
      phone(tester);
      await start(
        tester,
        auth: fakeRepository(
          withStoredToken: true,
          failDashboardWithCode: 'service_unavailable',
        ),
      );

      expect(find.text('Catatan belum dapat dimuat'), findsOneWidget);
      expect(find.text('Coba lagi'), findsOneWidget);
    });

    testWidgets('records money and refreshes the ledger', (tester) async {
      phone(tester);
      final fake = fakeAuth(
        withStoredToken: true,
        accountList: [ledgerAccount(name: 'Tunai')],
      );
      await start(tester, auth: fake.repository);

      await tester.tap(find.text('Catat uang'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), '286500');
      await tester.enterText(find.byType(TextFormField).at(1), 'Belanja rumah');
      await tester.tap(find.text('Simpan catatan'));
      await tester.pumpAndSettle();

      expect(fake.backend.lastTransactionBody?['amount_atomic'], 286500);
      expect(fake.backend.lastTransactionBody?['description'], 'Belanja rumah');
      expect(fake.backend.lastTransactionBody?['transaction_type'], 'expense');
      expect(find.text('Simpan catatan'), findsNothing,
          reason: 'a saved entry closes the sheet');
    });

    testWidgets('formats the amount as it is typed', (tester) async {
      phone(tester);
      await start(
        tester,
        auth: fakeRepository(
          withStoredToken: true,
          accountList: [ledgerAccount(name: 'Tunai')],
        ),
      );
      await tester.tap(find.text('Catat uang'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), '1250000');
      await tester.pump();
      expect(find.text('1.250.000'), findsOneWidget,
          reason: 'a long number is far easier to check when grouped');
    });

    testWidgets('switching to income sends the other direction',
        (tester) async {
      phone(tester);
      final fake = fakeAuth(
        withStoredToken: true,
        accountList: [ledgerAccount(name: 'Tunai')],
      );
      await start(tester, auth: fake.repository);

      await tester.tap(find.text('Catat uang'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Masuk'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).at(0), '4000000');
      await tester.enterText(find.byType(TextFormField).at(1), 'Gaji');
      await tester.tap(find.text('Simpan catatan'));
      await tester.pumpAndSettle();

      expect(fake.backend.lastTransactionBody?['transaction_type'], 'income');
    });

    testWidgets('a blank form never reaches the server', (tester) async {
      phone(tester);
      final fake = fakeAuth(
        withStoredToken: true,
        accountList: [ledgerAccount(name: 'Tunai')],
      );
      await start(tester, auth: fake.repository);

      await tester.tap(find.text('Catat uang'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan catatan'));
      await tester.pump();

      expect(find.text('Isi jumlahnya.'), findsOneWidget);
      expect(find.text('Tulis keperluannya.'), findsOneWidget);
      expect(fake.backend.lastTransactionBody, isNull);
    });

    testWidgets('a retry reuses the same idempotency key', (tester) async {
      phone(tester);
      final fake = fakeAuth(
        withStoredToken: true,
        accountList: [ledgerAccount(name: 'Tunai')],
        failTransactionWithCode: 'service_unavailable',
      );
      await start(tester, auth: fake.repository);

      await tester.tap(find.text('Catat uang'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), '50000');
      await tester.enterText(find.byType(TextFormField).at(1), 'Kopi');
      await tester.tap(find.text('Simpan catatan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan catatan'));
      await tester.pumpAndSettle();

      // Two attempts at the same entry must not be able to post twice.
      expect(fake.backend.transactionKeys, hasLength(2));
      expect(
        fake.backend.transactionKeys.first,
        fake.backend.transactionKeys.last,
      );
    });

    testWidgets('a rejected save keeps the form and says why', (tester) async {
      phone(tester);
      await start(
        tester,
        auth: fakeRepository(
          withStoredToken: true,
          accountList: [ledgerAccount(name: 'Tunai')],
          failTransactionWithCode: 'ledger_write_denied',
        ),
      );

      await tester.tap(find.text('Catat uang'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), '1000');
      await tester.enterText(find.byType(TextFormField).at(1), 'Uji');
      await tester.tap(find.text('Simpan catatan'));
      await tester.pumpAndSettle();

      expect(find.byType(AuthErrorNote), findsOneWidget);
      expect(find.text('Simpan catatan'), findsOneWidget);
    });

    testWidgets('a transfer needs two accounts and says so with one',
        (tester) async {
      phone(tester);
      await start(
        tester,
        auth: fakeRepository(
          withStoredToken: true,
          accountList: [ledgerAccount(name: 'Tunai')],
        ),
      );

      await tester.tap(find.text('Pindah dana'));
      await tester.pumpAndSettle();
      expect(find.textContaining('butuh dua akun'), findsOneWidget);
    });

    testWidgets('a transfer sends both accounts', (tester) async {
      phone(tester);
      final fake = fakeAuth(
        withStoredToken: true,
        accountList: [
          ledgerAccount(name: 'Tunai', id: '11111111-1111-1111-1111-111111111111'),
          ledgerAccount(name: 'Bank', id: '22222222-2222-2222-2222-222222222222'),
        ],
      );
      await start(tester, auth: fake.repository);

      await tester.tap(find.text('Pindah dana'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, '1000000');
      await tester.tap(find.text('Pindahkan'));
      await tester.pumpAndSettle();

      expect(fake.backend.lastTransferBody?['from_account_id'],
          '11111111-1111-1111-1111-111111111111');
      expect(fake.backend.lastTransferBody?['to_account_id'],
          '22222222-2222-2222-2222-222222222222');
      expect(fake.backend.lastTransferBody?['amount_atomic'], 1000000);
    });
  });

  group('email forwarding setup', () {
    Future<FakeAuth> openSetup(
      WidgetTester tester, {
      Map<String, dynamic>? address,
    }) async {
      final fake = fakeAuth(withStoredToken: true, inboxAddress: address);
      await start(tester, auth: fake.repository);
      await tester.tap(find.byTooltip('Buka profil'));
      await tester.pumpAndSettle();
      // The sheet scrolls on a short screen, so the button may be below the
      // fold when the actions grow.
      await tester.scrollUntilVisible(
        find.text('Catatan dari email'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Catatan dari email'));
      await tester.pumpAndSettle();
      return fake;
    }

    testWidgets('explains the limit before asking for anything',
        (tester) async {
      phone(tester);
      await openSetup(tester);

      expect(find.textContaining('tidak pernah membuka kotak masukmu'),
          findsOneWidget,
          reason: 'the privacy boundary is the reason this design exists');
      expect(find.text('Buat alamat rumah'), findsOneWidget);
    });

    testWidgets('creating an address shows the steps', (tester) async {
      phone(tester);
      final fake = await openSetup(tester);

      await tester.tap(find.text('Buat alamat rumah'));
      await tester.pumpAndSettle();

      expect(fake.backend.inboxAddressCreated, isTrue);
      expect(find.text('rumpun-abc123@mail.example.com'), findsOneWidget);
      expect(find.text('Salin alamat rumahmu'), findsOneWidget);
    });

    testWidgets("shows Gmail's code once it arrives", (tester) async {
      phone(tester);
      await openSetup(
        tester,
        address: inboxAddressJson(verificationCode: '123456789'),
      );

      expect(find.text('123456789'), findsOneWidget,
          reason: 'digging the code out of a mailbox is the annoying part');
    });

    testWidgets('an active address reports what it has received',
        (tester) async {
      phone(tester);
      await openSetup(
        tester,
        address: inboxAddressJson(state: 'active', messageCount: 3),
      );

      expect(find.text('Sudah jalan'), findsOneWidget);
      expect(find.text('3 email sudah diterima.'), findsOneWidget);
    });

    testWidgets('the steps fit the narrowest phone', (tester) async {
      phone(tester, size: const Size(320, 568));
      await openSetup(
        tester,
        address: inboxAddressJson(
          address: 'rumpun-0123456789abcdef@mail.example.com',
          verificationCode: '123456789',
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the review inbox', () {
    testWidgets('confirming sends the candidate and its version',
        (tester) async {
      phone(tester);
      final fake = fakeAuth(
        withStoredToken: true,
        candidates: [
          candidateJson(description: 'Toko kebutuhan rumah', amount: 286500),
        ],
      );
      await start(tester, auth: fake.repository);
      await tester.tap(find.text('Tinjau'));
      await tester.pumpAndSettle();

      expect(find.text('Toko kebutuhan rumah'), findsOneWidget);
      expect(find.text('Rp 286.500'), findsOneWidget);

      await tester.tap(find.text('Masukkan ke catatan'));
      await tester.pumpAndSettle();
      expect(fake.backend.confirmedCandidateId, candidateId);
    });

    testWidgets('a candidate missing an amount cannot be confirmed',
        (tester) async {
      phone(tester);
      await start(
        tester,
        auth: fakeRepository(
          withStoredToken: true,
          candidates: [candidateJson(description: 'Pembayaran', amount: null)],
        ),
      );
      await tester.tap(find.text('Tinjau'));
      await tester.pumpAndSettle();

      expect(find.text('Jumlah belum terbaca'), findsOneWidget);
      final confirm = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Masukkan ke catatan'));
      expect(confirm.enabled, isFalse,
          reason: 'confirming a half-read email would post a wrong number');
    });

    testWidgets('an empty inbox does not claim email is connected',
        (tester) async {
      phone(tester);
      await start(tester, auth: fakeRepository(withStoredToken: true));
      await tester.tap(find.text('Tinjau'));
      await tester.pumpAndSettle();

      expect(find.text('Tidak ada yang menunggu'), findsOneWidget);
    });
  });

  testWidgets('narrow phone layout has no render overflow', (tester) async {
    phone(tester, size: const Size(320, 568));
    await openHome(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Tinjau'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
