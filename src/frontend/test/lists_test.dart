import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumpun_frontend/main.dart';

import 'fake_backend.dart';

Future<FakeBackend> _openLists(WidgetTester tester, {Size? size}) async {
  tester.view.physicalSize = size ?? const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fake = fakeAuth(withStoredToken: true);
  await tester.pumpWidget(RumpunApp(auth: fake.repository));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Daftar'));
  await tester.pumpAndSettle();
  return fake.backend;
}

void main() {
  testWidgets('create a grocery list, add, check, and clear items', (
    tester,
  ) async {
    final backend = await _openLists(tester);
    expect(find.text('Bakulnya masih kosong'), findsOneWidget);
    expect(find.text('Kabari saat ada barang baru'), findsOneWidget);

    await tester.tap(find.text('Buat daftar pertama'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buat daftar'));
    await tester.pumpAndSettle();
    expect(find.text('Beri nama daftar dulu.'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Pasar'));
    await tester.tap(find.bySemanticsLabel('Aprikot'));
    await tester.enterText(find.byType(TextField).first, 'Belanja bulanan');
    await tester.tap(find.text('Buat daftar'));
    await tester.pumpAndSettle();

    expect(find.text('Belanja bulanan'), findsOneWidget);
    expect(find.textContaining('Geser ke kanan'), findsOneWidget);
    expect(backend.lists.single['icon'], 'market');
    expect(backend.lists.single['tint'], 'apricot');
    final composer = find.widgetWithText(
      TextField,
      'Tambah barang, mis. Telur 1 kg',
    );
    await tester.enterText(composer, 'Telur 1 kg');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    await tester.enterText(composer, 'Susu');
    await tester.tap(find.byTooltip('Tambahkan'));
    await tester.pumpAndSettle();

    final items = (backend.lists.single['items'] as List)
        .cast<Map<String, dynamic>>();
    expect(items.map((i) => (i['text'], i['quantity'])).toList(), [
      ('Telur', '1 kg'),
      ('Susu', null),
    ]);
    expect(find.text('Telur'), findsOneWidget);
    expect(find.text('1 kg'), findsOneWidget);
    expect(find.byTooltip('Ditambahkan Ibu Ratna'), findsNWidgets(2));

    await tester.tap(find.text('Telur'));
    await tester.pumpAndSettle();
    expect(items.first['checked'], isTrue);
    expect(find.text('Sudah dibeli (1)'), findsOneWidget);

    await tester.tap(find.byTooltip('Pilihan daftar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus yang sudah dibeli'));
    await tester.pumpAndSettle();
    expect(find.text('Telur'), findsNothing);
    expect(find.text('Susu'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('1 lagi'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('0 dari 1 sudah dibeli')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit an item and add a note', (tester) async {
    await _openLists(tester);
    await tester.tap(find.text('Buat daftar pertama'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Pasar');
    await tester.tap(find.text('Buat daftar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Tambah barang, mis. Telur 1 kg'),
      '2 ikat bayam',
    );
    await tester.tap(find.byTooltip('Tambahkan'));
    await tester.pumpAndSettle();
    expect(find.text('bayam'), findsOneWidget);
    await tester.tap(find.byTooltip('Ubah bayam'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Catatan (opsional)'),
      'yang segar',
    );
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(find.text('2 ikat · yang segar'), findsOneWidget);
  });

  testWidgets('free-form note warns before discarding unsaved text', (
    tester,
  ) async {
    final backend = await _openLists(tester);
    await tester.tap(find.text('Buat daftar pertama'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Servis AC');
    await tester.tap(find.text('Catatan bebas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buat daftar'));
    await tester.pumpAndSettle();

    final editor = find.widgetWithText(
      TextField,
      'Tulis catatan untuk seisi rumah…',
    );
    await tester.enterText(editor, 'Teknisi datang Sabtu');
    await tester.pumpAndSettle();
    expect(find.text('Ada perubahan belum disimpan.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Catatan belum disimpan'), findsOneWidget);
    await tester.tap(find.text('Kembali menulis'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan catatan'));
    await tester.pumpAndSettle();
    expect(backend.lists.single['body'], 'Teknisi datang Sabtu');
    expect(find.text('Tersimpan untuk seisi rumah.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Catatan'), findsOneWidget);
  });

  testWidgets('lists fit a 320 px phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final fake = fakeAuth(withStoredToken: true);
    fake.backend.lists.add({
      'id': 'list-x',
      'name': 'Belanja bulanan untuk seminggu ke depan',
      'kind': 'checklist',
      'version': 1,
      'body': '',
      'created_by': signedInName,
      'items': [
        {
          'id': 'i1',
          'text': 'Minyak goreng kemasan dua liter',
          'quantity': '2 botol',
          'note': 'merek apa saja',
          'checked': false,
          'added_by': signedInName,
        },
      ],
    });
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    await tester.pumpWidget(RumpunApp(auth: fake.repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daftar'));
    await tester.pumpAndSettle();
    FlutterError.onError = previous;
    expect(errors.map((e) => e.exceptionAsString()), isEmpty);
    FlutterError.onError = errors.add;
    await tester.tap(find.text('Belanja bulanan untuk seminggu ke depan'));
    await tester.pumpAndSettle();
    FlutterError.onError = previous;
    expect(errors.map((e) => e.exceptionAsString()), isEmpty);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/lists_detail_320.png'),
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Minyak goreng kemasan dua liter'), findsOneWidget);
  });
}
