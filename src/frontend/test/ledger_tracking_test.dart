import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumpun_frontend/api/models.dart';
import 'package:rumpun_frontend/main.dart';

import 'fake_backend.dart';

Future<void> openLedger(WidgetTester tester) async {
  final action = find.text('Lihat akun dan riwayat');
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

void main() {
  test('minor units stay exact across currencies', () {
    expect(const Money(atomic: 125000, currency: 'IDR').format(), 'Rp 125.000');
    expect(
      const Money(atomic: 125075, currency: 'USD').format(),
      'USD 1.250,75',
    );
    expect(
      const Money(atomic: 125075, currency: 'KWD').format(),
      'KWD 125,075',
    );
    expect(
      const Money(atomic: 123456789, currency: 'XAU', minorUnit: 8).format(),
      'XAU 1,23456789',
    );
    expect(parseMoneyInput('1.250,75', 2), 125075);
    expect(parseMoneyInput('1,23456789', 8), 123456789);
    expect(parseMoneyInput('1,234', 2), isNull);
  });

  testWidgets('creates a non-cash asset and records a precise valuation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = fakeAuth(withStoredToken: true);
    await tester.pumpWidget(RumpunApp(auth: fake.repository));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await openLedger(tester);

    await tester.tap(find.text('Tambah akun atau aset'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Emas keluarga');
    await tester.tap(find.text('Bank').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aset fisik').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), 'XAU');
    await tester.enterText(find.byType(TextFormField).at(2), '2');
    await tester.enterText(find.byType(TextFormField).at(3), 'gram');
    await tester.ensureVisible(find.text('Simpan akun'));
    await tester.tap(find.text('Simpan akun'));
    await tester.pumpAndSettle();

    expect(fake.backend.lastAccountBody?['currency'], 'XAU');
    expect(fake.backend.lastAccountBody?['kind'], 'physical_asset');
    expect(find.text('Emas keluarga'), findsOneWidget);
    await tester.tap(find.text('Emas keluarga'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '1250,75');
    await tester.enterText(find.byType(TextFormField).at(1), '3,125');
    await tester.ensureVisible(find.text('Catat nilai').last);
    await tester.tap(find.text('Catat nilai').last);
    await tester.pumpAndSettle();
    expect(fake.backend.lastValuationBody?['value_atomic'], 125075);
    expect(fake.backend.lastValuationBody?['quantity'], '3.125');
    expect(find.text('XAU 1.250,75'), findsOneWidget);
  });

  testWidgets('history opens an auditable reversal', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = fakeAuth(
      withStoredToken: true,
      transactionHistory: [
        ledgerEntry(description: 'Belanja pasar', amount: 75000),
      ],
    );
    await tester.pumpWidget(RumpunApp(auth: fake.repository));
    await tester.pumpAndSettle();
    await openLedger(tester);
    await tester.tap(find.text('Belanja pasar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Salah jumlah');
    await tester.ensureVisible(find.text('Batalkan transaksi'));
    await tester.tap(find.text('Batalkan transaksi'));
    await tester.pumpAndSettle();
    expect(fake.backend.lastReversalBody?['reason'], 'Salah jumlah');
  });

  testWidgets('opening balance is distinct from income', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = fakeAuth(
      withStoredToken: true,
      accountList: [ledgerAccount(name: 'Tabungan')],
    );
    await tester.pumpWidget(RumpunApp(auth: fake.repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Catat uang'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Masuk / keluar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saldo awal').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '250000');
    await tester.enterText(find.byType(TextFormField).at(1), 'Saldo pembuka');
    await tester.ensureVisible(find.text('Tanggal: hari ini'));
    await tester.tap(find.text('Tanggal: hari ini'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Simpan catatan'));
    await tester.tap(find.text('Simpan catatan'));
    await tester.pumpAndSettle();
    expect(
      fake.backend.lastTransactionBody?['transaction_type'],
      'opening_balance',
    );
    expect(fake.backend.lastTransactionBody?['amount_atomic'], 250000);
    expect(fake.backend.lastTransactionBody?['occurred_at'], isNotNull);
  });

  testWidgets('cross-currency transfer requires an explicit received amount', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = fakeAuth(
      withStoredToken: true,
      accountList: [
        ledgerAccount(
          name: 'Dollar',
          currency: 'USD',
          id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        ),
        ledgerAccount(
          name: 'Yen',
          currency: 'JPY',
          id: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        ),
      ],
    );
    await tester.pumpWidget(RumpunApp(auth: fake.repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pindah dana'));
    await tester.pumpAndSettle();
    expect(find.text('Jumlah diterima'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), '12,50');
    await tester.enterText(find.byType(TextFormField).at(1), '1800');
    await tester.ensureVisible(find.text('Pindahkan'));
    await tester.tap(find.text('Pindahkan'));
    await tester.pumpAndSettle();
    expect(fake.backend.lastTransferBody?['amount_atomic'], 1250);
    expect(fake.backend.lastTransferBody?['destination_amount_atomic'], 1800);
  });

  testWidgets('history pagination stops after the last page', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = fakeAuth(
      withStoredToken: true,
      transactionHistory: [ledgerEntry(description: 'Baru', amount: 1000)],
      laterTransactionHistory: [ledgerEntry(description: 'Lama', amount: 2000)],
    );
    await tester.pumpWidget(RumpunApp(auth: fake.repository));
    await tester.pumpAndSettle();
    await openLedger(tester);
    await tester.ensureVisible(find.text('Tampilkan lebih lama'));
    await tester.tap(find.text('Tampilkan lebih lama'));
    await tester.pumpAndSettle();
    expect(find.text('Baru'), findsOneWidget);
    expect(find.text('Lama'), findsOneWidget);
    expect(find.text('Tampilkan lebih lama'), findsNothing);
    expect(fake.backend.transactionListCalls, 2);
  });

  testWidgets('ledger and account form fit a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = fakeAuth(
      withStoredToken: true,
      accountList: [
        ledgerAccount(
          name: 'Investasi jangka panjang keluarga',
          id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          currency: 'LONGTOKEN123',
          kind: 'investment',
        ),
      ],
      accounts: [
        {
          'account_id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          'name': 'Investasi jangka panjang keluarga',
          'kind': 'investment',
          'currency': 'LONGTOKEN123',
          'minor_unit': 8,
          'balance_atomic': 900000000000000000,
        },
      ],
      transactionHistory: [
        ledgerEntry(
          description: 'Nilai aset lintas satuan',
          amount: 900000000000000000,
          currency: 'LONGTOKEN123',
        ),
      ],
    );
    await tester.pumpWidget(RumpunApp(auth: fake.repository));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await openLedger(tester);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Tambah akun atau aset'));
    await tester.tap(find.text('Tambah akun atau aset'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Simpan akun'));
    expect(tester.takeException(), isNull);
  });
}
