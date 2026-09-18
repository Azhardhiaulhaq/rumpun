import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumpun_frontend/main.dart';

Future<void> openLogin(WidgetTester tester) async {
  await tester.pumpWidget(const RumpunApp());
  await tester.tap(find.byType(InkWell).first);
  await tester.pumpAndSettle();
}

Future<void> openHome(WidgetTester tester) async {
  await openLogin(tester);
  final context = tester.element(find.text('Kembali ke rumah'));
  Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
  await tester.pumpAndSettle();
}

Future<void> chooseDemoState(WidgetTester tester, String state) async {
  await tester.tap(find.byTooltip('Ubah keadaan layar demo'));
  await tester.pump(const Duration(seconds: 1));
  final item = find.widgetWithText(PopupMenuItem<ViewState>, state);
  final popupItem = tester.widget<PopupMenuItem<ViewState>>(item);
  Navigator.of(tester.element(item)).pop(popupItem.value);
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('login validates, reveals password, and requests a reset link',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await openLogin(tester);
    expect(find.text('Kembali ke rumah'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'alamat-salah');
    await tester.enterText(find.byType(TextFormField).at(1), 'pendek');
    await tester.ensureVisible(find.text('Masuk ke Rumpun'));
    await tester.tap(find.text('Masuk ke Rumpun'));
    await tester.pump();
    expect(find.text('Masukkan alamat email yang valid.'), findsOneWidget);
    expect(find.text('Kata sandi minimal 8 karakter.'), findsOneWidget);

    await tester.tap(find.byTooltip('Tampilkan kata sandi'));
    await tester.pump();
    expect(find.byTooltip('Sembunyikan kata sandi'), findsOneWidget);

    await tester.tap(find.text('Lupa kata sandi?'));
    await tester.pumpAndSettle();
    expect(find.text('Atur ulang kata sandi'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'demo@rumpun.app');
    await tester.tap(find.text('Kirim tautan'));
    await tester.pumpAndSettle();
    expect(find.text('Tautan pemulihan demo sudah diminta.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('registration exposes Google, Apple, and email paths',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await openLogin(tester);
    await tester.ensureVisible(find.text('Buat akun keluarga'));
    await tester.tap(find.text('Buat akun keluarga'));
    await tester.pumpAndSettle();
    expect(find.text('Daftar dengan Google'), findsOneWidget);
    expect(find.text('Daftar dengan Apple'), findsOneWidget);

    await tester.ensureVisible(find.text('Buat akun dengan email'));
    await tester.tap(find.text('Buat akun dengan email'));
    await tester.pump();
    expect(find.text('Masukkan nama panggilan.'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'A');
    await tester.enterText(fields.at(1), 'a@rumpun.app');
    await tester.enterText(fields.at(2), 'katakunci-demo');
    await tester.tap(find.byTooltip('Tampilkan kata sandi'));
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Buat akun dengan email'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('Total dana keluarga'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Google and Apple registration actions both complete',
      (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await openLogin(tester);
    Navigator.of(tester.element(find.text('Kembali ke rumah')))
        .pushNamed('/register');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daftar dengan Google'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('Total dana keluarga'), findsOneWidget);

    Navigator.of(tester.element(find.text('Total dana keluarga')))
        .pushNamedAndRemoveUntil('/register', (_) => false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daftar dengan Apple'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('Total dana keluarga'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('home controls and data states perform their actions',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await openHome(tester);

    await tester.tap(find.byTooltip('Sembunyikan saldo'));
    await tester.pump();
    expect(find.text('Rp •••••••••'), findsOneWidget);

    await tester.tap(find.text('Catat uang'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan transaksi demo'));
    await tester.pump();
    expect(
        find.text('Isi keperluan dan jumlah terlebih dahulu.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Belanja demo');
    await tester.enterText(find.byType(TextField).at(1), '10000');
    await tester.tap(find.text('Simpan transaksi demo'));
    await tester.pumpAndSettle();
    expect(find.text('Simpan transaksi demo'), findsNothing);

    await tester.tap(find.text('Pindah dana'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Alur transfer akan memakai akun asli setelah backend terhubung.'),
        findsOneWidget);
    await tester.tap(find.text('Tutup pratinjau'));
    await tester.pumpAndSettle();

    await chooseDemoState(tester, 'Memuat');
    expect(find.text('Mengambil catatan rumah'), findsOneWidget);
    await chooseDemoState(tester, 'Kosong');
    expect(find.text('Belum ada catatan uang'), findsOneWidget);
    await tester.tap(find.text('Catat transaksi pertama'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Catat uang'))).pop();
    await tester.pumpAndSettle();
    await chooseDemoState(tester, 'Galat');
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(find.text('Total dana keluarga'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('review supports confirmation, rejection, and all states',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await openHome(tester);
    await tester.tap(find.text('Tinjau'));
    await tester.pumpAndSettle();
    expect(find.text('Tinjau dulu'), findsOneWidget);

    await tester.tap(find.text('Toko kebutuhan rumah'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konfirmasi ke catatan'));
    await tester.pumpAndSettle();
    expect(find.text('Transaksi demo dikonfirmasi dan ditambahkan ke catatan.'),
        findsOneWidget);

    await tester.tap(find.text('Pembayaran layanan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konfirmasi ke catatan'));
    await tester.pump();
    expect(find.text('Konfirmasi ke catatan'), findsOneWidget);
    await tester.ensureVisible(find.text('Tolak usulan ini'));
    await tester.tap(find.text('Tolak usulan ini'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ya, tolak'));
    await tester.pumpAndSettle();
    expect(find.text('Semua sudah ditinjau'), findsOneWidget);

    await chooseDemoState(tester, 'Memuat');
    expect(find.text('Memeriksa email transaksi'), findsOneWidget);
    await chooseDemoState(tester, 'Galat');
    expect(find.text('Email belum dapat diperiksa'), findsOneWidget);
    await tester.tap(find.text('Sinkronkan lagi'));
    await tester.pumpAndSettle();
    expect(find.text('Semua sudah ditinjau'), findsOneWidget);
    await tester.tap(find.text('Periksa ulang email'));
    await tester.pump();
    expect(find.text('Semua sudah ditinjau'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('narrow phone layout has no render overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await openLogin(tester);
    Navigator.of(tester.element(find.text('Kembali ke rumah')))
        .pushNamedAndRemoveUntil('/home', (_) => false);
    await tester.pumpAndSettle();
    tester.takeException();
    await tester.tap(find.text('Tinjau'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
