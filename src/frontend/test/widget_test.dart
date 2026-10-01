import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumpun_frontend/api/auth_repository.dart';
import 'package:rumpun_frontend/gmail_connect_screen.dart';
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
      expect(
        find.byType(TextFormField),
        findsNothing,
        reason: 'there is no email or password form any more',
      );
      expect(find.text('Buat akun keluarga'), findsNothing);
    });

    testWidgets('a returning member lands straight on the ledger', (
      tester,
    ) async {
      phone(tester);
      final fake = fakeAuth();
      await start(tester, auth: fake.repository);
      await tapGoogle(tester);

      expect(fake.google.initialized, isTrue);
      expect(fake.google.authenticateCalls, 1);
      expect(find.text('Total aset keluarga'), findsOneWidget);
      expect(find.text('Halo, $signedInName'), findsOneWidget);
    });

    testWidgets('a first-time member is asked to name the household', (
      tester,
    ) async {
      phone(tester);
      await start(
        tester,
        auth: fakeRepository(isNewUser: true, householdNamed: false),
      );
      await tapGoogle(tester);

      expect(find.text('Halo, $signedInName'), findsOneWidget);
      expect(find.text('Nama rumah tangga'), findsOneWidget);
      expect(find.text('Total aset keluarga'), findsNothing);
    });

    testWidgets('dismissing the Google picker leaves the screen untouched', (
      tester,
    ) async {
      phone(tester);
      await start(tester, auth: fakeRepository(googleError: canceledPicker()));
      await tapGoogle(tester);

      expect(find.text('Masuk dengan Google'), findsOneWidget);
      expect(
        find.byType(AuthErrorNote),
        findsNothing,
        reason: 'cancelling is a choice, not an error',
      );
    });

    testWidgets('a server rejection is explained and the button comes back', (
      tester,
    ) async {
      phone(tester);
      await start(
        tester,
        auth: fakeRepository(failWithCode: 'invalid_google_token'),
      );
      await tapGoogle(tester);

      expect(
        find.text('Server menolak identitas Google ini. Coba masuk lagi.'),
        findsOneWidget,
      );
      expect(find.text('Masuk dengan Google'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).first).enabled,
        isTrue,
      );
    });

    testWidgets('a build without a client ID says so instead of hiding', (
      tester,
    ) async {
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

    testWidgets('rejects a blank name before calling the server', (
      tester,
    ) async {
      phone(tester);
      final fake = await openSetup(tester);

      await tester.enterText(find.byType(TextFormField).first, '   ');
      await tester.tap(find.text('Buka catatan rumah'));
      await tester.pump();

      expect(find.text('Beri nama rumah tanggamu.'), findsOneWidget);
      expect(fake.backend.lastSetupBody, isNull);
    });

    testWidgets('sends the name and currency, then opens the ledger', (
      tester,
    ) async {
      phone(tester);
      final fake = await openSetup(tester);

      await tester.enterText(find.byType(TextFormField).first, namedHousehold);
      await tester.tap(find.text('Buka catatan rumah'));
      await tester.pumpAndSettle();

      expect(fake.backend.lastSetupBody?['name'], namedHousehold);
      expect(fake.backend.lastSetupBody?['base_currency'], 'IDR');
      expect(find.text('Total aset keluarga'), findsOneWidget);
      expect(find.text(namedHousehold), findsOneWidget);
    });

    testWidgets('a rejected setup keeps the form and its values', (
      tester,
    ) async {
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

    testWidgets('the currency picker offers the currencies the API accepts', (
      tester,
    ) async {
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

      expect(find.text('Total aset keluarga'), findsOneWidget);
      expect(find.text('Masuk dengan Google'), findsNothing);
    });

    testWidgets('closing the app mid-setup returns to setup', (tester) async {
      phone(tester);
      await start(
        tester,
        auth: fakeRepository(withStoredToken: true, householdNamed: false),
      );

      expect(find.text('Nama rumah tangga'), findsOneWidget);
      expect(find.text('Total aset keluarga'), findsNothing);
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
    testWidgets('shows the household total and the accounts behind it', (
      tester,
    ) async {
      phone(tester);
      await start(
        tester,
        auth: fakeRepository(
          withStoredToken: true,
          accounts: [
            account(name: 'Dompet dapur', balance: 1250000),
            account(name: 'BCA', balance: 750000, kind: 'bank'),
          ],
        ),
      );

      expect(find.text('Rp 2.000.000'), findsOneWidget);
      expect(find.text('Tersebar di 2 akun'), findsOneWidget);

      // The breakdown is the answer to "where is that money", so it stays
      // closed until asked for, then opens as its own sheet rather than
      // pushing the charts off the screen.
      expect(find.text('Dompet dapur'), findsNothing);
      await tester.tap(find.text('Total aset keluarga'));
      await tester.pumpAndSettle();

      expect(find.text('Rincian aset'), findsOneWidget);
      expect(find.text('Dompet dapur'), findsOneWidget);
      expect(find.text('Rp 1.250.000'), findsOneWidget);
      expect(find.text('BCA'), findsOneWidget);
      expect(find.text('Rp 750.000'), findsOneWidget);
      // Grouped by kind, so a long list reads as a few kinds of money.
      expect(find.text('Rekening bank'), findsOneWidget);

      await tester.tap(find.byTooltip('Tutup'));
      await tester.pumpAndSettle();
      expect(find.text('Rincian aset'), findsNothing);
    });

    testWidgets('equity never appears as money the household holds', (
      tester,
    ) async {
      phone(tester);
      await start(
        tester,
        auth: fakeRepository(
          withStoredToken: true,
          accounts: [
            account(name: 'Tunai', balance: 1250000),
            // The balancing side of every entry. Showing it would double the
            // ledger and present a large negative account nobody recognises.
            account(
              name: 'Household equity',
              balance: -1250000,
              kind: 'equity',
            ),
          ],
        ),
      );

      expect(find.text('Tersebar di 1 akun'), findsOneWidget);
      await tester.tap(find.text('Total aset keluarga'));
      await tester.pumpAndSettle();
      expect(find.text('Household equity'), findsNothing);
    });

    testWidgets('a second currency is a separate card, never a sum', (
      tester,
    ) async {
      phone(tester);
      await start(
        tester,
        auth: fakeRepository(
          withStoredToken: true,
          accounts: [
            account(name: 'Tunai', balance: 1250000),
            account(
              name: 'Livin SGD',
              balance: 11800,
              kind: 'foreign_currency',
              currency: 'SGD',
            ),
          ],
        ),
      );

      expect(find.text('Rp 1.250.000'), findsOneWidget);
      // Adding the two would invent an exchange rate, so the SGD total lives
      // on its own card behind a swipe.
      expect(find.text('Total aset keluarga'), findsOneWidget);
      await tester.drag(
        find.text('Total aset keluarga'),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aset dalam SGD'), findsOneWidget);
      expect(find.text('SGD 118,00'), findsOneWidget);
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

    testWidgets('an empty ledger says so without claiming a failure', (
      tester,
    ) async {
      phone(tester);
      await start(tester, auth: fakeRepository(withStoredToken: true));

      expect(find.text('Rp 0'), findsOneWidget);
      expect(find.text('Belum ada akun terisi'), findsOneWidget);
      // No spending means no chart. An axis drawn through zeroes would look
      // like a reading rather than an absence of one.
      expect(
        find.textContaining('Grafik muncul setelah ada pengeluaran'),
        findsOneWidget,
      );
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
      expect(
        find.text('Simpan catatan'),
        findsNothing,
        reason: 'a saved entry closes the sheet',
      );
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
      expect(
        find.text('1.250.000'),
        findsOneWidget,
        reason: 'a long number is far easier to check when grouped',
      );
    });

    testWidgets('switching to income sends the other direction', (
      tester,
    ) async {
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

    testWidgets('a transfer needs two accounts and says so with one', (
      tester,
    ) async {
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
          ledgerAccount(
            name: 'Tunai',
            id: '11111111-1111-1111-1111-111111111111',
          ),
          ledgerAccount(
            name: 'Bank',
            id: '22222222-2222-2222-2222-222222222222',
          ),
        ],
      );
      await start(tester, auth: fake.repository);

      await tester.tap(find.text('Pindah dana'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, '1000000');
      await tester.tap(find.text('Pindahkan'));
      await tester.pumpAndSettle();

      expect(
        fake.backend.lastTransferBody?['from_account_id'],
        '11111111-1111-1111-1111-111111111111',
      );
      expect(
        fake.backend.lastTransferBody?['to_account_id'],
        '22222222-2222-2222-2222-222222222222',
      );
      expect(fake.backend.lastTransferBody?['amount_atomic'], 1000000);
    });
  });

  group('Gmail connection', () {
    testWidgets('OAuth return opens Gmail after a cold session restore', (
      tester,
    ) async {
      phone(tester);
      final links = StreamController<Uri>();
      addTearDown(links.close);
      await tester.pumpWidget(
        RumpunApp(
          auth: fakeRepository(withStoredToken: true),
          gmailReturnLinks: links.stream,
        ),
      );
      links.add(Uri.parse('rumpun://gmail-connected'));
      await tester.pumpAndSettle();

      expect(find.byType(GmailConnectScreen), findsOneWidget);
      expect(find.text('Temukan transaksi dari Gmail'), findsOneWidget);
    });

    testWidgets('OAuth return refreshes the open Gmail screen', (tester) async {
      phone(tester);
      final links = StreamController<Uri>();
      addTearDown(links.close);
      await tester.pumpWidget(
        RumpunApp(
          auth: fakeRepository(withStoredToken: true),
          gmailReturnLinks: links.stream,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Buka profil'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Hubungkan Gmail'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Hubungkan Gmail'));
      await tester.pumpAndSettle();

      links.add(Uri.parse('rumpun://gmail-connected'));
      await tester.pumpAndSettle();
      expect(find.byType(GmailConnectScreen), findsOneWidget);
      expect(find.text('Temukan transaksi dari Gmail'), findsOneWidget);
    });

    testWidgets('opens the backend-provided Google consent URL', (
      tester,
    ) async {
      phone(tester);
      final fake = fakeAuth(withStoredToken: true);
      await fake.repository.restore();
      Uri? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: GmailConnectScreen(
            auth: fake.repository,
            openUrl: (url) async {
              opened = url;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(opened?.host, 'accounts.google.com');
    });

    Future<FakeAuth> openSetup(
      WidgetTester tester, {
      Map<String, dynamic>? connection,
      Map<String, dynamic>? syncResult,
    }) async {
      final fake = fakeAuth(
        withStoredToken: true,
        gmailConnection: connection,
        gmailSyncResult: syncResult,
      );
      await start(tester, auth: fake.repository);
      await tester.tap(find.byTooltip('Buka profil'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Hubungkan Gmail'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Hubungkan Gmail'));
      await tester.pumpAndSettle();
      return fake;
    }

    testWidgets('explains the Gmail grant before connecting', (tester) async {
      phone(tester);
      await openSetup(tester);

      expect(
        find.textContaining('Google akan meminta izin membaca Gmail'),
        findsOneWidget,
      );
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('shows the connected account and pending messages', (
      tester,
    ) async {
      phone(tester);
      await openSetup(
        tester,
        connection: {
          'email': signedInEmail,
          'status': 'active',
          'connected_at': '2026-09-26T00:00:00Z',
          'last_synced_at': '2026-09-26T00:30:00Z',
          'awaiting_jev_count': 3,
        },
      );

      expect(find.text(signedInEmail), findsOneWidget);
      expect(
        find.text('3 email menunggu pemeriksaan transaksi.'),
        findsOneWidget,
      );
      expect(find.text('Putuskan Gmail'), findsOneWidget);
    });

    testWidgets('disconnect removes the connection', (tester) async {
      phone(tester);
      final fake = await openSetup(
        tester,
        connection: {
          'email': signedInEmail,
          'status': 'active',
          'connected_at': '2026-09-26T00:00:00Z',
          'last_synced_at': null,
          'awaiting_jev_count': 0,
        },
      );
      await tester.tap(find.text('Putuskan Gmail'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Putuskan'));
      await tester.pumpAndSettle();

      expect(fake.backend.gmailDisconnected, isTrue);
      expect(find.text('Temukan transaksi dari Gmail'), findsOneWidget);
    });

    testWidgets('sync requests the chosen lookback', (tester) async {
      phone(tester);
      final fake = await openSetup(
        tester,
        connection: {
          'email': signedInEmail,
          'status': 'active',
          'connected_at': '2026-09-26T00:00:00Z',
          'last_synced_at': null,
          'awaiting_jev_count': 0,
          'classification_enabled': true,
        },
      );
      await tester.tap(find.text('2 hari terakhir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('7 hari terakhir').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sinkronkan Gmail'));
      await tester.pumpAndSettle();
      expect(fake.backend.lastGmailSyncDays, 7);
      expect(find.textContaining('0 usulan baru'), findsOneWidget);
    });

    const activeConnection = {
      'email': signedInEmail,
      'status': 'active',
      'connected_at': '2026-09-26T00:00:00Z',
      'last_synced_at': null,
      'awaiting_jev_count': 0,
      'classification_enabled': true,
    };

    testWidgets('sync with emails left for retry still reports its results', (
      tester,
    ) async {
      phone(tester);
      await openSetup(
        tester,
        connection: activeConnection,
        syncResult: {
          'discovered_count': 120,
          'candidate_count': 44,
          'unclassified_count': 4,
        },
      );
      await tester.tap(find.text('Sinkronkan Gmail'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '44 usulan baru dari 120 email baru. 4 email belum selesai '
          'diperiksa. Rumpun akan mencobanya lagi otomatis.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('gagal'), findsNothing);
    });

    testWidgets('failed sync still says which proposals arrived', (
      tester,
    ) async {
      phone(tester);
      await openSetup(
        tester,
        connection: activeConnection,
        syncResult: {
          'status': 'failed',
          'discovered_count': 120,
          'candidate_count': 12,
          'error_code': 'ConnectionError',
        },
      );
      await tester.tap(find.text('Sinkronkan Gmail'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '12 usulan baru sudah masuk ke Tinjau, tetapi pemeriksaan '
          'terhenti. Coba lagi nanti.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('reconnect state fits the narrowest phone', (tester) async {
      phone(tester, size: const Size(320, 568));
      await openSetup(
        tester,
        connection: {
          'email': 'a-long-account-name@example.com',
          'status': 'reauthorization_required',
          'connected_at': '2026-09-26T00:00:00Z',
          'last_synced_at': null,
          'awaiting_jev_count': 0,
        },
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the review inbox', () {
    testWidgets('detail edits amount description account type and category', (
      tester,
    ) async {
      phone(tester);
      final fake = fakeAuth(
        withStoredToken: true,
        candidates: [candidateJson(description: 'Belanja', amount: 50000)],
        accountList: [ledgerAccount(name: 'BCA', id: bcaId)],
      );
      await start(tester, auth: fake.repository);
      await tester.tap(find.text('Tinjau'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Belanja'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ubah usulan'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '75000');
      await tester.enterText(find.byType(TextField).at(1), 'Gaji freelance');
      await tester.tap(find.text('Pengeluaran'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pemasukan').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Masuk ke akun'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BCA').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kategori'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('General income').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Simpan perubahan'));
      await tester.tap(find.text('Simpan perubahan'));
      await tester.pumpAndSettle();
      final body = fake.backend.lastCandidateEditBody;
      expect(body?['amount_atomic'], 75000);
      expect(body?['description'], 'Gaji freelance');
      expect(body?['account_id'], bcaId);
      expect(body?['transaction_type'], 'income');
      expect(body?['category_id'], 'ffffffff-ffff-ffff-ffff-ffffffffffff');
      expect(body?['occurred_at'], isNotNull);
    });
    testWidgets('Jago card opens details with recipient and account', (
      tester,
    ) async {
      phone(tester);
      final fake = fakeAuth(
        withStoredToken: true,
        candidates: [
          candidateJson(
            description: 'Kantin Bude Surati, TN AB',
            amount: 286500,
            recipientName: 'Kantin Bude Surati, TN AB',
            recipientAccount: '9360091436625580712',
          ),
        ],
      );
      await start(tester, auth: fake.repository);
      await tester.tap(find.text('Tinjau'));
      await tester.pumpAndSettle();
      expect(find.text('Kantin Bude Surati, TN AB'), findsOneWidget);
      expect(find.text('9360091436625580712'), findsOneWidget);
      await tester.tap(find.text('Kantin Bude Surati, TN AB'));
      await tester.pumpAndSettle();
      expect(find.text('Detail usulan'), findsOneWidget);
      expect(find.text('9360091436625580712'), findsOneWidget);
      expect(find.text('Subjek email'), findsOneWidget);
      expect(fake.backend.confirmedCandidateId, isNull);
    });

    test('loads later pages so older email proposals stay available', () async {
      final fake = fakeAuth(
        withStoredToken: true,
        candidates: [
          for (var index = 0; index < 120; index++)
            candidateJson(description: 'Email $index', amount: 1000 + index),
        ],
      );
      expect(await fake.repository.restore(), isTrue);
      final result = await fake.repository.candidates();
      expect(result.items, hasLength(120));
      expect(result.items.last.description, 'Email 119');
    });

    testWidgets('confirming asks which account paid, then posts it', (
      tester,
    ) async {
      phone(tester);
      final fake = fakeAuth(
        withStoredToken: true,
        candidates: [
          candidateJson(
            description: 'Toko kebutuhan rumah',
            amount: 286500,
            issuer: 'Jago',
          ),
        ],
        accountList: [
          ledgerAccount(name: 'BCA (Azhar)', id: bcaId),
          ledgerAccount(name: 'Jago (Azhar)', id: jagoAzharId),
          ledgerAccount(name: 'Jago (Lita)', id: jagoLitaId),
          ledgerAccount(
            name: 'Gold Bar',
            id: 'b0000000-0000-0000-0000-000000000009',
            kind: 'physical_asset',
          ),
        ],
      );
      await start(tester, auth: fake.repository);
      await tester.tap(find.text('Tinjau'));
      await tester.pumpAndSettle();

      expect(find.text('Toko kebutuhan rumah'), findsOneWidget);
      expect(find.text('Rp 286.500'), findsOneWidget);
      expect(find.text('Dari email Jago'), findsOneWidget);

      await tester.tap(find.text('Masukkan ke catatan'));
      await tester.pumpAndSettle();
      expect(
        fake.backend.confirmedCandidateId,
        isNull,
        reason: 'nothing posts until an account is chosen',
      );

      // Two Jago accounts: guessing would post to the wrong person's money.
      await tester.tap(find.text('Simpan catatan'));
      await tester.pumpAndSettle();
      expect(find.text('Pilih dulu akun yang membayar.'), findsOneWidget);
      expect(fake.backend.confirmedCandidateId, isNull);

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      expect(
        find.text('Gold Bar'),
        findsNothing,
        reason: 'a card payment cannot come out of a gold bar',
      );
      await tester.tap(find.text('Jago (Lita)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan catatan'));
      await tester.pumpAndSettle();

      expect(fake.backend.confirmedCandidateId, candidateId);
      expect(fake.backend.lastConfirmBody, {
        'version': 1,
        'account_id': jagoLitaId,
        'category_id': 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
      });
      expect(
        fake.backend.confirmIdempotencyKey,
        'candidate-confirm-$candidateId-v1-$jagoLitaId-'
        'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
        reason: 'the API refuses to post a candidate without a replay key',
      );
      expect(find.text('Simpan catatan'), findsNothing);
      expect(find.textContaining('Idempotency-Key'), findsNothing);
    });

    testWidgets('a pocket transfer opens with Jev\'s accounts to check', (
      tester,
    ) async {
      phone(tester);
      const pocketId = 'b0000000-0000-0000-0000-000000000004';
      final fake = fakeAuth(
        withStoredToken: true,
        candidates: [
          candidateJson(
            description: 'Money arrived in your Shared Pocket',
            amount: 50000,
            direction: 'transfer',
            issuer: 'Jago',
            accountId: jagoAzharId,
            destinationAccountId: pocketId,
            suggestedFields: ['account_id', 'destination_account_id'],
          ),
        ],
        accountList: [
          ledgerAccount(name: 'Jago (Azhar)', id: jagoAzharId),
          ledgerAccount(name: 'Jago (Lita)', id: jagoLitaId),
          ledgerAccount(
            name: 'Food and Drink Pocket',
            id: pocketId,
            kind: 'budget_envelope',
          ),
        ],
      );
      await start(tester, auth: fake.repository);
      await tester.tap(find.text('Tinjau'));
      await tester.pumpAndSettle();

      expect(
        find.text('Perlu dilengkapi sebelum bisa dikonfirmasi'),
        findsNothing,
        reason: 'the accounts are chosen while confirming',
      );
      await tester.tap(find.text('Masukkan ke catatan'));
      await tester.pumpAndSettle();

      expect(find.text('Jago (Azhar)'), findsOneWidget);
      expect(find.text('Food and Drink Pocket'), findsOneWidget);
      expect(find.text('Saran Jev, ubah bila keliru'), findsNWidgets(2));

      // The person disagrees about the source; only Jev's other pick stays marked.
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jago (Lita)').last);
      await tester.pumpAndSettle();
      expect(find.text('Saran Jev, ubah bila keliru'), findsOneWidget);

      await tester.tap(find.text('Simpan catatan'));
      await tester.pumpAndSettle();
      expect(fake.backend.lastConfirmBody, {
        'version': 1,
        'account_id': jagoLitaId,
        'destination_account_id': pocketId,
      });
    });

    testWidgets('the only account at the sending bank is preselected', (
      tester,
    ) async {
      phone(tester);
      final fake = fakeAuth(
        withStoredToken: true,
        candidates: [
          candidateJson(description: 'Kopi', amount: 11300, issuer: 'BCA'),
        ],
        accountList: [
          ledgerAccount(name: 'BCA (Azhar)', id: bcaId),
          ledgerAccount(name: 'Jago (Azhar)', id: jagoAzharId),
        ],
      );
      await start(tester, auth: fake.repository);
      await tester.tap(find.text('Tinjau'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Masukkan ke catatan'));
      await tester.pumpAndSettle();

      expect(find.text('BCA (Azhar)'), findsOneWidget);
      await tester.tap(find.text('Simpan catatan'));
      await tester.pumpAndSettle();
      expect(fake.backend.lastConfirmBody?['account_id'], bcaId);
    });

    testWidgets('money arriving by email is offered as income', (tester) async {
      phone(tester);
      final fake = fakeAuth(
        withStoredToken: true,
        candidates: [
          candidateJson(
            description: 'Money arrived in your Shared Pocket',
            amount: 100000,
            direction: 'income',
          ),
        ],
      );
      await start(tester, auth: fake.repository);
      await tester.tap(find.text('Tinjau'));
      await tester.pumpAndSettle();

      expect(find.text('Pemasukan dari email'), findsOneWidget);
      final confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Masukkan ke catatan'),
      );
      expect(
        confirm.enabled,
        isTrue,
        reason: 'income can now be recorded with an income category',
      );
      final reject = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Tolak'),
      );
      expect(reject.enabled, isTrue);
    });

    testWidgets('a candidate missing an amount cannot be confirmed', (
      tester,
    ) async {
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
        find.widgetWithText(FilledButton, 'Masukkan ke catatan'),
      );
      expect(
        confirm.enabled,
        isFalse,
        reason: 'confirming a half-read email would post a wrong number',
      );
    });

    testWidgets('an empty inbox does not claim email is connected', (
      tester,
    ) async {
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
