import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

void main() {
  runApp(const RumpunApp());
}

class RumpunApp extends StatelessWidget {
  const RumpunApp({super.key});

  @override
  Widget build(BuildContext context) {
    const forest = Color(0xFF234B38);
    const ink = Color(0xFF20251F);
    const paper = Color(0xFFF7F1E7);
    const cream = Color(0xFFFFFBF4);
    const clay = Color(0xFFA44B2B);

    final scheme = ColorScheme.fromSeed(
      seedColor: forest,
      brightness: Brightness.light,
      primary: forest,
      onPrimary: Colors.white,
      secondary: clay,
      onSecondary: Colors.white,
      surface: cream,
      onSurface: ink,
      error: const Color(0xFF9F2D24),
      onError: Colors.white,
    );

    return MaterialApp(
      title: 'Rumpun',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: paper,
        fontFamily: 'NotoSans',
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontFamily: 'NotoSerif',
            fontWeight: FontWeight.w700,
            fontSize: 48,
            height: 1.03,
            letterSpacing: -1.2,
          ),
          headlineLarge: TextStyle(
            fontFamily: 'NotoSerif',
            fontWeight: FontWeight.w700,
            fontSize: 34,
            height: 1.12,
            letterSpacing: -0.5,
          ),
          headlineMedium: TextStyle(
            fontFamily: 'NotoSerif',
            fontWeight: FontWeight.w700,
            fontSize: 26,
            height: 1.2,
          ),
          titleLarge: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            height: 1.25,
          ),
          titleMedium: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            height: 1.3,
          ),
          bodyLarge: TextStyle(fontSize: 16, height: 1.5),
          bodyMedium: TextStyle(fontSize: 14, height: 1.45),
          labelLarge: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: cream,
          labelStyle: const TextStyle(color: Color(0xFF455047)),
          hintStyle: const TextStyle(color: Color(0xFF59635B)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF7A837B)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF7A837B)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: forest, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF9F2D24), width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(44, 52),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: ink,
            minimumSize: const Size(44, 52),
            side: const BorderSide(color: Color(0xFF5F6B61)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: forest,
            minimumSize: const Size(44, 44),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: ink,
          contentTextStyle: TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const SplashScreen(),
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/home': (_) => const AppShell(),
      },
    );
  }
}

class AppColors {
  static const forest = Color(0xFF234B38);
  static const moss = Color(0xFF6F8265);
  static const clay = Color(0xFFA44B2B);
  static const paper = Color(0xFFF7F1E7);
  static const cream = Color(0xFFFFFBF4);
  static const ink = Color(0xFF20251F);
  static const mutedInk = Color(0xFF4F5B52);
  static const line = Color(0xFF70736B);
  static const paleMoss = Color(0xFFDCE5D7);
  static const paleClay = Color(0xFFF3D8CA);
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1450), () {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.forest,
      body: SafeArea(
        child: InkWell(
          onTap: () {
            _timer?.cancel();
            Navigator.pushReplacementNamed(context, '/login');
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                right: -54,
                top: 42,
                child: Opacity(
                  opacity: 0.24,
                  child: CustomPaint(
                    size: const Size(280, 410),
                    painter:
                        BranchPainter(color: AppColors.paper, strokeWidth: 2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(flex: 4),
                    Text(
                      'Rumpun',
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                            color: AppColors.paper,
                            fontSize: 58,
                          ),
                    ),
                    const SizedBox(height: 12),
                    const SizedBox(
                      width: 270,
                      child: Text(
                        'Uang keluarga, dirawat bersama.',
                        style: TextStyle(
                          color: Color(0xFFE5E9DD),
                          fontSize: 18,
                          height: 1.45,
                        ),
                      ),
                    ),
                    const Spacer(flex: 5),
                    const Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.paper,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Menyiapkan rumahmu',
                          style: TextStyle(color: Color(0xFFE5E9DD)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.forest,
            borderRadius: BorderRadius.circular(13),
          ),
          child: CustomPaint(
            painter: MiniBranchPainter(),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'Rumpun',
          style: Theme.of(context)
              .textTheme
              .headlineMedium
              ?.copyWith(fontSize: 25),
        ),
      ],
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BrandHeader(),
            const SizedBox(height: 46),
            Text('Kembali ke rumah',
                style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 10),
            const Text(
              'Masuk untuk melihat catatan keuangan keluargamu.',
              style: TextStyle(
                  color: AppColors.mutedInk, fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 32),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'nama@email.com',
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty || !text.contains('@')) {
                  return 'Masukkan alamat email yang valid.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Kata sandi',
                suffixIcon: IconButton(
                  tooltip: _obscure
                      ? 'Tampilkan kata sandi'
                      : 'Sembunyikan kata sandi',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                ),
              ),
              validator: (value) {
                if ((value ?? '').length < 8) {
                  return 'Kata sandi minimal 8 karakter.';
                }
                return null;
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _showResetDialog(context),
                child: const Text('Lupa kata sandi?'),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Text('Masuk ke Rumpun'),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                const Expanded(child: Divider(color: AppColors.line)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('belum punya akun',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                const Expanded(child: Divider(color: AppColors.line)),
              ],
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: () => Navigator.pushNamed(context, '/register'),
              child: const Text('Buat akun keluarga'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showResetDialog(BuildContext context) async {
  final controller = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Atur ulang kata sandi'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.emailAddress,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Email akun'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal')),
        FilledButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Tautan pemulihan demo sudah diminta.')),
            );
          },
          child: const Text('Kirim tautan'),
        ),
      ],
    ),
  );
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _agree = false;
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _finishRegistration(String method) async {
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Pendaftaran demo melalui $method berhasil.')),
    );
    Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
  }

  void _submitEmail() {
    if (!_formKey.currentState!.validate()) return;
    if (!_agree) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Setujui ketentuan demo untuk melanjutkan.')),
      );
      return;
    }
    _finishRegistration('email');
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      showBack: true,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BrandHeader(),
            const SizedBox(height: 34),
            Text('Mulai satu catatan bersama',
                style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 10),
            const Text(
              'Buat akunmu. Rumah tangga dapat disiapkan setelah masuk.',
              style: TextStyle(
                  color: AppColors.mutedInk, fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 26),
            OutlinedButton.icon(
              onPressed: _loading ? null : () => _finishRegistration('Google'),
              icon: const Text('G',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              label: const Text('Daftar dengan Google'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loading ? null : () => _finishRegistration('Apple'),
              icon: const Icon(Icons.apple, size: 22),
              label: const Text('Daftar dengan Apple'),
            ),
            const SizedBox(height: 24),
            const Row(
              children: [
                Expanded(child: Divider(color: AppColors.line)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('atau gunakan email'),
                ),
                Expanded(child: Divider(color: AppColors.line)),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                  labelText: 'Nama panggilan',
                  hintText: 'Nama yang keluarga kenal'),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Masukkan nama panggilan.'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                  labelText: 'Email', hintText: 'nama@email.com'),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty || !text.contains('@')) {
                  return 'Masukkan alamat email yang valid.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submitEmail(),
              decoration: InputDecoration(
                labelText: 'Kata sandi',
                helperText: 'Minimal 8 karakter',
                suffixIcon: IconButton(
                  tooltip: _obscure
                      ? 'Tampilkan kata sandi'
                      : 'Sembunyikan kata sandi',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                ),
              ),
              validator: (value) => (value ?? '').length < 8
                  ? 'Kata sandi minimal 8 karakter.'
                  : null,
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _agree,
              onChanged: (value) => setState(() => _agree = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              title: const Text(
                'Saya memahami ini purwarupa dan data di dalamnya adalah data demo.',
                style: TextStyle(fontSize: 13.5, height: 1.4),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading ? null : _submitEmail,
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Text('Buat akun dengan email'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Sudah punya akun? Masuk'),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child, this.showBack = false});

  final Widget child;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              right: -96,
              top: 64,
              child: Opacity(
                opacity: 0.12,
                child: CustomPaint(
                  size: const Size(250, 360),
                  painter: BranchPainter(color: AppColors.forest),
                ),
              ),
            ),
            SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(24, showBack ? 64 : 34, 24, 42),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: child,
                ),
              ),
            ),
            if (showBack)
              Positioned(
                top: 6,
                left: 8,
                child: IconButton(
                  tooltip: 'Kembali',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [HomeScreen(), ReviewScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        backgroundColor: AppColors.cream,
        indicatorColor: AppColors.paleMoss,
        height: 72,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Beranda',
          ),
          NavigationDestination(
            icon: Badge(
              label: Text('2'),
              child: Icon(Icons.fact_check_outlined),
            ),
            selectedIcon: Badge(
              label: Text('2'),
              child: Icon(Icons.fact_check),
            ),
            label: 'Tinjau',
          ),
        ],
      ),
    );
  }
}

enum ViewState { ready, loading, empty, error }

class StateMenu extends StatelessWidget {
  const StateMenu({super.key, required this.value, required this.onChanged});

  final ViewState value;
  final ValueChanged<ViewState> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ViewState>(
      tooltip: 'Ubah keadaan layar demo',
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => const [
        PopupMenuItem(value: ViewState.ready, child: Text('Data demo')),
        PopupMenuItem(value: ViewState.loading, child: Text('Memuat')),
        PopupMenuItem(value: ViewState.empty, child: Text('Kosong')),
        PopupMenuItem(value: ViewState.error, child: Text('Galat')),
      ],
      icon: const Icon(Icons.more_horiz),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ViewState _state = ViewState.ready;
  bool _balanceVisible = true;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Rumah demo',
                          style: TextStyle(
                              color: AppColors.mutedInk, fontSize: 13)),
                      Text('Selamat pagi, A',
                          style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                ),
                StateMenu(
                    value: _state,
                    onChanged: (value) => setState(() => _state = value)),
                const SizedBox(width: 2),
                Semantics(
                  button: true,
                  label: 'Buka profil demo',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => _showProfileSheet(context),
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                          color: AppColors.paleClay, shape: BoxShape.circle),
                      child: const Text('A',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 18)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildState()),
        ],
      ),
    );
  }

  Widget _buildState() {
    switch (_state) {
      case ViewState.loading:
        return const DataStateView(
          icon: Icons.sync,
          title: 'Mengambil catatan rumah',
          message: 'Saldo demo dan catatan terbaru sedang dimuat.',
          loading: true,
        );
      case ViewState.empty:
        return DataStateView(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Belum ada catatan uang',
          message:
              'Tambahkan transaksi pertama untuk mulai melihat ringkasan rumah.',
          actionLabel: 'Catat transaksi pertama',
          onAction: () => _showAddTransaction(context),
        );
      case ViewState.error:
        return DataStateView(
          icon: Icons.cloud_off_outlined,
          title: 'Catatan belum dapat dimuat',
          message:
              'Periksa koneksi, lalu coba mengambil data rumah sekali lagi.',
          actionLabel: 'Coba lagi',
          onAction: () => setState(() => _state = ViewState.ready),
        );
      case ViewState.ready:
        return _buildReady();
    }
  }

  Widget _buildReady() {
    return RefreshIndicator(
      color: AppColors.forest,
      onRefresh: () async {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Data demo sudah diperbarui.')),
          );
        }
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 22, 18, 20),
            decoration: BoxDecoration(
              color: AppColors.forest,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -30,
                  top: -40,
                  child: Opacity(
                    opacity: 0.15,
                    child: CustomPaint(
                      size: const Size(150, 210),
                      painter: BranchPainter(
                          color: AppColors.paper, strokeWidth: 1.5),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Total dana keluarga',
                              style: TextStyle(color: Color(0xFFE5E9DD))),
                        ),
                        IconButton(
                          tooltip: _balanceVisible
                              ? 'Sembunyikan saldo'
                              : 'Tampilkan saldo',
                          onPressed: () => setState(
                              () => _balanceVisible = !_balanceVisible),
                          color: AppColors.paper,
                          icon: Icon(_balanceVisible
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _balanceVisible ? 'Rp 12.450.000' : 'Rp •••••••••',
                      style:
                          Theme.of(context).textTheme.headlineLarge?.copyWith(
                                color: Colors.white,
                                fontFamily: 'NotoSans',
                                fontSize: 30,
                              ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'DATA DEMO · 3 akun',
                      style: TextStyle(
                          color: Color(0xFFE5E9DD),
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: QuickAction(
                  icon: Icons.add,
                  label: 'Catat uang',
                  filled: true,
                  onTap: () => _showAddTransaction(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: QuickAction(
                  icon: Icons.swap_horiz,
                  label: 'Pindah dana',
                  onTap: () => _showTransfer(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          const SectionHeading(
              title: 'Yang perlu dilihat',
              subtitle: 'Data contoh untuk menilai tampilan'),
          const SizedBox(height: 14),
          InkWell(
            onTap: () {
              final shell = context.findAncestorStateOfType<_AppShellState>();
              shell?.setState(() => shell._index = 1);
            },
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.paleClay,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF7E321B)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.cream,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.mark_email_unread_outlined,
                        color: AppColors.clay),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('2 transaksi menunggu',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        SizedBox(height: 3),
                        Text('Periksa hasil baca email sebelum masuk catatan.'),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
          const SizedBox(height: 30),
          const SectionHeading(title: 'Catatan terbaru'),
          const SizedBox(height: 10),
          const TransactionRow(
            icon: Icons.shopping_basket_outlined,
            title: 'Belanja rumah',
            subtitle: 'Tunai · data demo',
            amount: '−Rp 286.500',
          ),
          const Divider(height: 1, indent: 58),
          const TransactionRow(
            icon: Icons.payments_outlined,
            title: 'Pemasukan keluarga',
            subtitle: 'Bank utama · data demo',
            amount: '+Rp 4.000.000',
            positive: true,
          ),
          const Divider(height: 1, indent: 58),
          const TransactionRow(
            icon: Icons.local_cafe_outlined,
            title: 'Makan bersama',
            subtitle: 'Dompet digital · data demo',
            amount: '−Rp 94.000',
          ),
        ],
      ),
    );
  }
}

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  ViewState _state = ViewState.ready;
  final List<ReviewCandidate> _items = [
    const ReviewCandidate(
      merchant: 'Toko kebutuhan rumah',
      amount: 'Rp 286.500',
      source: 'Email transaksi · data demo',
      account: 'Bank utama',
      confidence: 'Cocok kuat',
      date: 'Hari ini, 08.42',
    ),
    const ReviewCandidate(
      merchant: 'Pembayaran layanan',
      amount: 'Rp 149.000',
      source: 'Email transaksi · data demo',
      account: 'Belum dipilih',
      confidence: 'Perlu dilengkapi',
      date: 'Kemarin, 19.14',
      needsInput: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 19, 10, 10),
            child: Row(
              children: [
                Expanded(
                    child: Text('Tinjau dulu',
                        style: Theme.of(context).textTheme.headlineLarge)),
                StateMenu(
                    value: _state,
                    onChanged: (value) => setState(() => _state = value)),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 22),
            child: Text(
              'Email hanya menjadi usulan. Kamu yang memutuskan apa yang masuk ke catatan.',
              style: TextStyle(color: AppColors.mutedInk, height: 1.5),
            ),
          ),
          const SizedBox(height: 18),
          Expanded(child: _buildState()),
        ],
      ),
    );
  }

  Widget _buildState() {
    if (_state == ViewState.loading) {
      return const DataStateView(
        icon: Icons.mark_email_read_outlined,
        title: 'Memeriksa email transaksi',
        message:
            'Rumpun sedang mengambil usulan yang cocok dengan aturan emailmu.',
        loading: true,
      );
    }
    if (_state == ViewState.error) {
      return DataStateView(
        icon: Icons.sync_problem_outlined,
        title: 'Email belum dapat diperiksa',
        message:
            'Tidak ada perubahan pada catatan keuangan. Coba sinkronkan lagi.',
        actionLabel: 'Sinkronkan lagi',
        onAction: () => setState(() => _state = ViewState.ready),
      );
    }
    if (_state == ViewState.empty || _items.isEmpty) {
      return DataStateView(
        icon: Icons.done_all,
        title: 'Semua sudah ditinjau',
        message: 'Tidak ada usulan transaksi yang menunggu keputusanmu.',
        actionLabel: 'Periksa ulang email',
        onAction: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Pemeriksaan demo selesai. Belum ada usulan baru.')),
          );
        },
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final item = _items[index];
        return ReviewCard(
          candidate: item,
          onTap: () => _showReviewDetail(context, item, index),
        );
      },
    );
  }

  Future<void> _showReviewDetail(
      BuildContext context, ReviewCandidate candidate, int index) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => ReviewDetail(candidate: candidate),
    );
    if (!mounted || result == null) return;
    setState(() => _items.removeAt(index));
    final message = result == 'confirmed'
        ? 'Transaksi demo dikonfirmasi dan ditambahkan ke catatan.'
        : 'Usulan demo ditolak. Catatan keuangan tidak berubah.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class ReviewCandidate {
  const ReviewCandidate({
    required this.merchant,
    required this.amount,
    required this.source,
    required this.account,
    required this.confidence,
    required this.date,
    this.needsInput = false,
  });

  final String merchant;
  final String amount;
  final String source;
  final String account;
  final String confidence;
  final String date;
  final bool needsInput;
}

class ReviewCard extends StatelessWidget {
  const ReviewCard({super.key, required this.candidate, required this.onTap});

  final ReviewCandidate candidate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cream,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            border: Border.all(
                color: candidate.needsInput
                    ? const Color(0xFF7E321B)
                    : AppColors.line),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: candidate.needsInput
                          ? AppColors.paleClay
                          : AppColors.paleMoss,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      candidate.needsInput
                          ? Icons.help_outline
                          : Icons.receipt_long_outlined,
                      color: candidate.needsInput
                          ? AppColors.clay
                          : AppColors.forest,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(candidate.merchant,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 3),
                        Text(candidate.date,
                            style: const TextStyle(color: AppColors.mutedInk)),
                      ],
                    ),
                  ),
                  Text(candidate.amount,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 14),
              DetailLine(label: 'Dari', value: candidate.source),
              const SizedBox(height: 8),
              DetailLine(label: 'Akun', value: candidate.account),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(
                    candidate.needsInput
                        ? Icons.info_outline
                        : Icons.check_circle_outline,
                    size: 18,
                    color: candidate.needsInput
                        ? const Color(0xFF9F3F22)
                        : AppColors.forest,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      candidate.confidence,
                      style: TextStyle(
                        color: candidate.needsInput
                            ? const Color(0xFF7E321B)
                            : AppColors.forest,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReviewDetail extends StatefulWidget {
  const ReviewDetail({super.key, required this.candidate});

  final ReviewCandidate candidate;

  @override
  State<ReviewDetail> createState() => _ReviewDetailState();
}

class _ReviewDetailState extends State<ReviewDetail> {
  late final TextEditingController _merchant;
  late final TextEditingController _amount;
  String? _account;

  @override
  void initState() {
    super.initState();
    _merchant = TextEditingController(text: widget.candidate.merchant);
    _amount = TextEditingController(
        text: widget.candidate.amount.replaceAll(RegExp(r'[^0-9]'), ''));
    _account = widget.candidate.needsInput ? null : 'Bank utama';
  }

  @override
  void dispose() {
    _merchant.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(22, 12, 22, math.max(24, keyboard + 16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 24),
          Text('Periksa sebelum dicatat',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(widget.candidate.source,
              style: const TextStyle(color: AppColors.mutedInk)),
          const SizedBox(height: 24),
          TextField(
            controller: _merchant,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Nama transaksi'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration:
                const InputDecoration(labelText: 'Jumlah', prefixText: 'Rp '),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _account,
            decoration: const InputDecoration(labelText: 'Catat dari akun'),
            items: const [
              DropdownMenuItem(value: 'Bank utama', child: Text('Bank utama')),
              DropdownMenuItem(value: 'Tunai', child: Text('Tunai')),
              DropdownMenuItem(
                  value: 'Dompet digital', child: Text('Dompet digital')),
            ],
            onChanged: (value) => setState(() => _account = value),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: AppColors.paleMoss,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, color: AppColors.forest),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Belum ada perubahan pada saldo. Data baru dicatat setelah kamu mengonfirmasi.',
                    style: TextStyle(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              if (_merchant.text.trim().isEmpty ||
                  _amount.text.trim().isEmpty ||
                  _account == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Lengkapi nama, jumlah, dan akun sebelum mengonfirmasi.')),
                );
                return;
              }
              Navigator.pop(context, 'confirmed');
            },
            child: const Text('Konfirmasi ke catatan'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => _confirmReject(context),
            child: const Text('Tolak usulan ini'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReject(BuildContext context) async {
    final reject = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tolak usulan?'),
        content: const Text(
            'Usulan ditandai ditolak. Saldo dan catatan transaksi tidak berubah.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ya, tolak')),
        ],
      ),
    );
    if (reject == true && mounted) Navigator.pop(context, 'rejected');
  }
}

class QuickAction extends StatelessWidget {
  const QuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? Colors.white : AppColors.ink;
    return Material(
      color: filled ? AppColors.clay : AppColors.cream,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: filled ? null : Border.all(color: AppColors.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 21),
              const SizedBox(width: 9),
              Flexible(
                child: Text(label,
                    style: TextStyle(
                        color: foreground, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        if (subtitle != null)
          Flexible(
            child: Text(
              subtitle!,
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppColors.mutedInk, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class TransactionRow extends StatelessWidget {
  const TransactionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amount,
    this.positive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String amount;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title, $amount, data demo',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.paleMoss,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: AppColors.forest, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.mutedInk, fontSize: 13)),
                ],
              ),
            ),
            Text(
              amount,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: positive ? AppColors.forest : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DetailLine extends StatelessWidget {
  const DetailLine({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(label,
              style: const TextStyle(color: AppColors.mutedInk, fontSize: 13)),
        ),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700))),
      ],
    );
  }
}

class DataStateView extends StatelessWidget {
  const DataStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.loading = false,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                    color: AppColors.paleMoss, shape: BoxShape.circle),
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(23),
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: AppColors.forest),
                      )
                    : Icon(icon, color: AppColors.forest, size: 32),
              ),
              const SizedBox(height: 22),
              Text(title,
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: 9),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.mutedInk, height: 1.5),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 22),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showAddTransaction(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final title = TextEditingController();
  final amount = TextEditingController();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.cream,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (sheetContext) {
      final bottom = MediaQuery.viewInsetsOf(sheetContext).bottom;
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(22, 22, 22, math.max(24, bottom + 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Catat uang',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            const Text(
                'Form ini menyimpan data demo hanya selama aplikasi terbuka.'),
            const SizedBox(height: 22),
            TextField(
              controller: title,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Keperluan'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Jumlah', prefixText: 'Rp '),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () {
                if (title.text.trim().isEmpty || amount.text.trim().isEmpty) {
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Isi keperluan dan jumlah terlebih dahulu.')),
                  );
                  return;
                }
                Navigator.pop(sheetContext);
                messenger.showSnackBar(
                  const SnackBar(
                      content: Text('Transaksi demo berhasil dicatat.')),
                );
              },
              child: const Text('Simpan transaksi demo'),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> _showTransfer(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: AppColors.cream,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pindah dana',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text(
              'Alur transfer akan memakai akun asli setelah backend terhubung.'),
          const SizedBox(height: 22),
          OutlinedButton(
            onPressed: () => Navigator.pop(sheetContext),
            child: const Text('Tutup pratinjau'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showProfileSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: AppColors.cream,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.paleClay,
                child: Text('A',
                    style: TextStyle(
                        color: AppColors.ink, fontWeight: FontWeight.w700)),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Profil demo',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 18)),
                    Text('Pemilik rumah',
                        style: TextStyle(color: AppColors.mutedInk)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(sheetContext);
              Navigator.pushNamedAndRemoveUntil(
                  context, '/login', (_) => false);
            },
            icon: const Icon(Icons.logout),
            label: const Text('Keluar dari purwarupa'),
          ),
        ],
      ),
    ),
  );
}

class BranchPainter extends CustomPainter {
  BranchPainter({required this.color, this.strokeWidth = 2.2});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final leaf = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final trunk = Path()
      ..moveTo(size.width * 0.46, size.height)
      ..cubicTo(
        size.width * 0.38,
        size.height * 0.73,
        size.width * 0.65,
        size.height * 0.55,
        size.width * 0.48,
        size.height * 0.31,
      )
      ..cubicTo(
        size.width * 0.40,
        size.height * 0.20,
        size.width * 0.48,
        size.height * 0.10,
        size.width * 0.44,
        0,
      );
    canvas.drawPath(trunk, line);

    final branches = [
      [0.49, 0.30, 0.78, 0.15],
      [0.51, 0.43, 0.22, 0.27],
      [0.52, 0.56, 0.82, 0.43],
      [0.43, 0.68, 0.15, 0.55],
    ];
    for (final points in branches) {
      final path = Path()
        ..moveTo(size.width * points[0], size.height * points[1])
        ..quadraticBezierTo(
          size.width * ((points[0] + points[2]) / 2),
          size.height * points[1],
          size.width * points[2],
          size.height * points[3],
        );
      canvas.drawPath(path, line);
      canvas.save();
      canvas.translate(size.width * points[2], size.height * points[3]);
      canvas.rotate(points[2] > points[0] ? -0.55 : 0.55);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 36, height: 17), leaf);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant BranchPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

class MiniBranchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.paper
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(12, 35)
      ..quadraticBezierTo(19, 24, 19, 9)
      ..moveTo(18, 22)
      ..quadraticBezierTo(28, 20, 32, 13)
      ..moveTo(18, 28)
      ..quadraticBezierTo(10, 25, 8, 19);
    canvas.drawPath(path, paint);
    final leaf = Paint()..color = AppColors.paper;
    canvas.drawOval(const Rect.fromLTWH(27, 8, 8, 5), leaf);
    canvas.drawOval(const Rect.fromLTWH(5, 15, 8, 5), leaf);
    canvas.drawOval(const Rect.fromLTWH(16, 6, 6, 8), leaf);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
