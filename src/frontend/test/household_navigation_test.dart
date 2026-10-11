import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumpun_frontend/main.dart';
import 'package:rumpun_frontend/household_home.dart';
import 'fake_backend.dart';

void main() {
  testWidgets('three cards reflow with large text and reduced motion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RumpunApp(auth: fakeRepository(withStoredToken: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rumah kita'), findsOneWidget);
    final context = tester.element(find.text('Rumah kita'));
    final media = MediaQuery.of(context);
    final auth = fakeRepository(withStoredToken: true);
    await auth.restore();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: media.copyWith(
            textScaler: const TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: HouseholdHome(
              auth: auth,
              onFinance: (_) {},
              onProfile: () {},
              onRecord: () async => false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Rincian aset'), 150);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Rincian aset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rincian aset'));
    await tester.pumpAndSettle();
    expect(find.text('Tutup rincian'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Lokasi keluarga'), 150);
    expect(find.text('Buka lokasi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('household home groups finance and labels location honestly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RumpunApp(auth: fakeRepository(withStoredToken: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Keuangan'), findsOneWidget);
    expect(find.text('Perlu ditinjau'), findsNothing);
    await tester.scrollUntilVisible(find.text('Lokasi keluarga'), 200);
    expect(find.text('Buka lokasi'), findsOneWidget);
    await tester.tap(find.text('Keuangan'));
    await tester.pumpAndSettle();
    expect(find.text('Ringkasan'), findsOneWidget);
    expect(find.text('Total aset'), findsOneWidget);
    expect(find.text('Rumah kita'), findsNothing);
    expect(find.text('Lihat akun dan riwayat'), findsNothing);
    expect(find.textContaining('Halo,'), findsNothing);
    await tester.tap(find.text('Riwayat'));
    await tester.pumpAndSettle();
    expect(find.text('Riwayat transaksi'), findsOneWidget);
    expect(find.text('Tambah akun atau aset'), findsNothing);
    await tester.tap(find.text('Tinjau'));
    await tester.pumpAndSettle();
    expect(find.text('Tidak ada yang menunggu'), findsOneWidget);
    await tester.ensureVisible(find.text('Akun & aset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Akun & aset'));
    await tester.pumpAndSettle();
    expect(find.text('Tambah akun atau aset'), findsOneWidget);
    expect(find.text('Riwayat transaksi'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'attention opens review without posting and recording offers three choices',
    (tester) async {
      await tester.pumpWidget(
        RumpunApp(
          auth: fakeRepository(
            withStoredToken: true,
            candidates: [candidateJson(description: 'Belanja', amount: 1000)],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Tinjau 1 usulan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tinjau 1 usulan'));
      await tester.pumpAndSettle();
      expect(find.text('Belanja'), findsOneWidget);
      await tester.tap(find.text('Beranda'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Catat uang'), 200);
      await tester.tap(find.text('Catat uang'));
      await tester.pumpAndSettle();
      expect(find.text('Pengeluaran'), findsOneWidget);
      expect(find.text('Pemasukan'), findsOneWidget);
      expect(find.text('Transfer antar akun'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
