import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'api/auth_repository.dart';
import 'api/models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(RumpunApp(auth: AuthRepository()));
}

/// Turns backend error codes and plugin exceptions into sentences a household
/// member can act on. Unmapped codes fall through to the server's own message.
String describeAuthError(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'google_login_not_configured':
        return 'Masuk dengan Google belum aktif di server ini.';
      case 'invalid_google_token':
      case 'invalid_google_issuer':
      case 'invalid_google_audience':
        return 'Server menolak identitas Google ini. Coba masuk lagi.';
      case 'unverified_google_identity':
        return 'Email Google ini belum diverifikasi oleh Google.';
      case 'google_identity_conflict':
        return 'Akun Google ini sudah tertaut ke pengguna lain.';
      case 'user_inactive':
        return 'Akun ini sedang dinonaktifkan.';
      case 'household_edit_denied':
        return 'Hanya pemilik rumah yang bisa mengubah data ini.';
      case 'unsupported_currency':
        return 'Mata uang itu belum didukung.';
      case 'invite_already_resolved':
        return 'Undangan ini sudah tidak berlaku.';
      case 'invite_not_found':
        return 'Undangan ini tidak ditemukan lagi.';
      case 'household_already_joined':
        return 'Akun ini sudah tergabung di sebuah rumah tangga.';
      case 'already_a_member':
        return 'Orang itu sudah ada di rumah ini.';
      case 'invite_already_sent':
        return 'Alamat itu sudah punya undangan yang menunggu.';
      case 'cannot_invite_yourself':
        return 'Kamu sudah ada di rumah ini.';
      case 'authentication_required':
      case 'invalid_access_token':
        return 'Sesi berakhir. Masuk lagi untuk lanjut.';
      case 'rate_limited':
        return 'Terlalu banyak percobaan. Tunggu sebentar.';
      default:
        return error.message;
    }
  }
  if (error is NetworkException) return error.message;
  if (error is GoogleNotConfigured) {
    return 'Aplikasi ini dibangun tanpa Google client ID.';
  }
  if (error is GoogleSignInException) {
    return switch (error.code) {
      GoogleSignInExceptionCode.canceled => '',
      GoogleSignInExceptionCode.interrupted =>
        'Proses Google terputus. Coba lagi.',
      GoogleSignInExceptionCode.providerConfigurationError =>
        'Konfigurasi Google belum cocok dengan aplikasi ini.',
      _ => 'Masuk dengan Google gagal. Coba lagi.',
    };
  }
  return 'Terjadi kesalahan yang tidak terduga.';
}

/// Where a signed-in user belongs: the ledger, the choice between creating and
/// joining a household, or the form that names a household created earlier.
String routeAfterSignIn(AuthRepository auth) {
  if (auth.needsOnboarding) return '/onboarding';
  if (auth.needsHouseholdSetup) return '/setup';
  return '/home';
}

class RumpunApp extends StatelessWidget {
  const RumpunApp({super.key, required this.auth});

  final AuthRepository auth;

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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: ink,
            minimumSize: const Size(44, 52),
            side: const BorderSide(color: Color(0xFF5F6B61)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
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
        '/': (_) => SplashScreen(auth: auth),
        '/login': (_) => LoginScreen(auth: auth),
        '/onboarding': (_) => OnboardingScreen(auth: auth),
        '/setup': (_) => HouseholdSetupScreen(auth: auth),
        '/home': (_) => AppShell(auth: auth),
      },
    );
  }
}

/// Shared surface and motion tokens. Kept together so the screens built after
/// these two inherit the same language instead of re-deciding it each time.
class AppColors {
  /// White, not paper, on the screens that should feel like a clean sheet.
  /// Paper stays the ground for the ledger itself, where warmth suits columns
  /// of numbers better than glare.
  static const surface = Color(0xFFFFFFFF);
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

  /// 4.53:1 on white. The lightest ink allowed to carry normal-size text.
  static const quietInk = Color(0xFF747775);

  /// Hairline rules on white. Non-text, so it sits below the 4.5:1 bar by
  /// design; it separates, it never has to be read.
  static const hairline = Color(0xFFE4E0D8);
}

/// Radii carry meaning: the tile is the brand mark, controls are softer than
/// containers, and nothing is a pill. A pill on every element would erase the
/// difference between an input and a card.
class AppRadius {
  static const mark = 16.0;
  static const control = 14.0;
  static const container = 20.0;
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.auth});

  final AuthRepository auth;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _markScale;
  late final Animation<double> _markFade;
  late final Animation<double> _wordFade;
  late final Animation<Offset> _wordRise;

  @override
  void initState() {
    super.initState();
    // The motion covers the token-restore wait, so the first frame is not a
    // frozen logo. It plays once and stops; a looping splash would keep asking
    // for attention after it has nothing left to say.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    // The mark settles rather than bounces: the brand is a tended plant, not a
    // notification.
    _markScale = Tween<double>(begin: 0.86, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.62, curve: Curves.easeOutCubic),
      ),
    );
    _markFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.45, curve: Curves.easeOut),
    );
    // The name follows the mark by a beat, so the eye reads symbol then word
    // instead of both at once.
    _wordFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.32, 0.85, curve: Curves.easeOut),
    );
    _wordRise = Tween<Offset>(begin: const Offset(0, 0.42), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.32, 1, curve: Curves.easeOutCubic),
          ),
        );

    _resume();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A stored refresh token means the household can skip the sign-in screen.
  /// Someone who closed the app mid-onboarding lands back where they stopped.
  Future<void> _resume() async {
    final restored = await widget.auth.restore();
    // Let the mark finish settling before leaving, so a fast restore does not
    // flash the screen away mid-animation.
    await _controller.forward().orCancel.catchError((_) {});
    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      restored ? routeAfterSignIn(widget.auth) : '/login',
    );
  }

  @override
  Widget build(BuildContext context) {
    // Reduced-motion users get the finished frame, never the journey.
    final animate = !MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      backgroundColor: AppColors.forest,
      body: Semantics(
        label: 'Rumpun sedang menyiapkan aplikasi',
        // Optical centre, not geometric: a block placed at exact centre reads
        // as sitting low, so it is lifted by a few percent of the height.
        child: Align(
          alignment: const Alignment(0, -0.08),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (animate)
                FadeTransition(
                  opacity: _markFade,
                  child: ScaleTransition(
                    scale: _markScale,
                    child: const BrandMark(size: 96),
                  ),
                )
              else
                const BrandMark(size: 96),
              const SizedBox(height: 24),
              if (animate)
                FadeTransition(
                  opacity: _wordFade,
                  child: SlideTransition(
                    position: _wordRise,
                    child: const _SplashWordmark(),
                  ),
                )
              else
                const _SplashWordmark(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplashWordmark extends StatelessWidget {
  const _SplashWordmark();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Rumpun',
      style: Theme.of(context).textTheme.displayLarge?.copyWith(
        color: AppColors.paper,
        fontSize: 44,
        letterSpacing: -0.4,
      ),
    );
  }
}

/// The branch motif on its own tile, at any size. Shared by the splash and the
/// sign-in screen so the mark is one object, not two drawings that drift apart.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, required this.size, this.onForest = true});

  final double size;

  /// On forest the tile is paper-on-forest; on white it carries forest itself.
  final bool onForest;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onForest ? const Color(0xFF2E5C46) : AppColors.forest,
        borderRadius: BorderRadius.circular(size * (AppRadius.mark / 56)),
      ),
      child: CustomPaint(painter: MiniBranchPainter(scale: size / 42)),
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
          child: const CustomPaint(painter: MiniBranchPainter()),
        ),
        const SizedBox(width: 12),
        Text(
          'Rumpun',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontSize: 25),
        ),
      ],
    );
  }
}

/// The only way into Rumpun. Google carries the identity, so there is no email
/// or password form to keep in sync with the backend's rules.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthRepository auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.auth.signInWithGoogle();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        routeAfterSignIn(widget.auth),
        (_) => false,
      );
    } catch (error) {
      if (!mounted) return;
      final message = describeAuthError(error);
      setState(() {
        _loading = false;
        _error = message.isEmpty ? null : message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      // White, not paper: the entry screen reads as a clean sheet, and it is
      // also the surface Google's button was designed against.
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                      child: Column(
                        // The content sits centred as one block, and the
                        // action anchors to the bottom of that block rather
                        // than the bottom of the screen, so a tablet does not
                        // strand the button far from the words.
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Align, not a bare BrandMark: the column stretches
                          // its children, which would smear the square tile
                          // across the full width.
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: BrandMark(size: 60, onForest: false),
                          ),
                          const SizedBox(height: 32),
                          Text(
                            'Masuk ke Rumpun',
                            style: textTheme.headlineLarge,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Satu tempat untuk semua urusan uang rumah: '
                            'pemasukan, pengeluaran, dan rencana bersama.',
                            style: TextStyle(
                              color: AppColors.mutedInk,
                              fontSize: 15.5,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 32),
                          if (_error != null) ...[
                            AuthErrorNote(message: _error!),
                            const SizedBox(height: 16),
                          ],
                          if (widget.auth.isConfigured)
                            GoogleSignInButton(
                              loading: _loading,
                              onPressed: _signIn,
                            )
                          else
                            const AuthErrorNote(
                              message:
                                  'Aplikasi ini dibangun tanpa Google '
                                  'client ID, jadi belum bisa dipakai masuk. '
                                  'Hubungi tim Rumpun.',
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Google's brand guidelines require their own mark on the button, so this is
/// drawn rather than borrowed from the Material icon set.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.loading,
    required this.onPressed,
  });

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Google's sign-in guidelines fix the surface, the mark, and the label.
    // The only thing left to us is the radius, which follows our control
    // token so the button belongs to this app and not to a generic form.
    return FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F1F1F),
        disabledBackgroundColor: const Color(0xFFF3F1EC),
        disabledForegroundColor: AppColors.quietInk,
        side: const BorderSide(color: Color(0xFF747775)),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        minimumSize: const Size(44, 56),
      ),
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: AppColors.forest,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const CustomPaint(
                  size: Size(20, 20),
                  painter: GoogleMarkPainter(),
                ),
                const SizedBox(width: 12),
                const Flexible(
                  child: Text(
                    'Masuk dengan Google',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Inline failure note. Sits next to the control that failed so the reason is
/// readable while retrying, unlike a snackbar that slides away.
class AuthErrorNote extends StatelessWidget {
  const AuthErrorNote({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7E4E0),
          borderRadius: BorderRadius.circular(10),
          border: const Border(
            left: BorderSide(color: Color(0xFF9F2D24), width: 3),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, size: 19, color: Color(0xFF7E2119)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF5E1912),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mirrors MembershipRole in `src/backend/app/models.py`.
const roleLabels = <String, String>{
  'owner': 'Pemilik rumah',
  'admin': 'Pengurus',
  'member': 'Anggota',
  'viewer': 'Pengamat',
  'child': 'Anak',
};

/// Mirrors SUPPORTED_CURRENCIES in `src/backend/app/routers/household.py`. The
/// server rejects anything outside this set, so the picker must not offer more.
const supportedCurrencies = <String, String>{
  'IDR': 'Rupiah',
  'MYR': 'Ringgit',
  'SGD': 'Dolar Singapura',
  'USD': 'Dolar AS',
  'EUR': 'Euro',
  'AUD': 'Dolar Australia',
  'JPY': 'Yen',
  'GBP': 'Pound',
};

/// Shown after sign-in while the user belongs to no household. Google proves
/// who they are but says nothing about which family they are part of, so this
/// is where that is settled: start a household, or accept one that invited you.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.auth});

  final AuthRepository auth;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  String? _busyInviteId;
  bool _loading = false;
  String? _error;

  List<InviteSummary> get _invites => widget.auth.pendingInvites;

  Future<void> _run(String? inviteId, Future<void> Function() action) async {
    // Two taps in the same frame both arrive before setState rebuilds, so the
    // guard lives here rather than only on the button's enabled state.
    if (_loading) return;
    setState(() {
      _busyInviteId = inviteId;
      _loading = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _busyInviteId = null;
        _loading = false;
      });
      if (!widget.auth.needsOnboarding) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busyInviteId = null;
        _loading = false;
        _error = describeAuthError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.auth.session?.user.displayName ?? '';
    final invites = _invites;

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BrandHeader(),
          const SizedBox(height: 34),
          Text(
            name.isEmpty ? 'Selamat datang' : 'Halo, $name',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 10),
          Text(
            invites.isEmpty
                ? 'Mulai rumah tanggamu sendiri, lalu undang anggota keluarga '
                      'lewat email mereka.'
                : 'Ada keluarga yang mengundangmu. Terima undangan itu, atau '
                      'mulai rumah tanggamu sendiri.',
            style: const TextStyle(
              color: AppColors.mutedInk,
              fontSize: 16,
              height: 1.55,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 20),
            AuthErrorNote(message: _error!),
          ],
          const SizedBox(height: 28),
          for (final invite in invites) ...[
            InviteCard(
              invite: invite,
              busy: _busyInviteId == invite.id,
              disabled: _loading,
              onAccept: () =>
                  _run(invite.id, () => widget.auth.acceptInvite(invite.id)),
              onDecline: () =>
                  _run(invite.id, () => widget.auth.declineInvite(invite.id)),
            ),
            const SizedBox(height: 14),
          ],
          if (invites.isNotEmpty) const SizedBox(height: 10),
          if (invites.isEmpty)
            FilledButton(
              onPressed: _loading ? null : () => _openCreate(context),
              child: const Text('Buat rumah tangga baru'),
            )
          else
            OutlinedButton(
              onPressed: _loading ? null : () => _openCreate(context),
              child: const Text('Buat rumah tangga sendiri'),
            ),
          const SizedBox(height: 18),
          Text(
            'Diundang tapi belum muncul? Undangan dikirim ke '
            '${widget.auth.session?.user.email ?? 'emailmu'}.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.mutedInk,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  void _openCreate(BuildContext context) =>
      Navigator.pushNamed(context, '/setup');
}

/// One invitation, with both answers weighted differently: accepting is the
/// action the card is for, declining is deliberately quieter.
class InviteCard extends StatelessWidget {
  const InviteCard({
    super.key,
    required this.invite,
    required this.busy,
    required this.disabled,
    required this.onAccept,
    required this.onDecline,
  });

  final InviteSummary invite;
  final bool busy;
  final bool disabled;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(16),
        // Cream on paper is only 1.09:1, so the border is what makes the card
        // an object rather than a lighter patch of the page.
        border: Border.all(color: AppColors.moss, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            invite.householdName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            '${invite.invitedByName} mengundangmu sebagai '
            '${roleLabels[invite.role] ?? invite.role}.',
            style: const TextStyle(
              color: AppColors.mutedInk,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: disabled ? null : onAccept,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'Gabung ${invite.householdName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          TextButton(
            onPressed: disabled ? null : onDecline,
            child: const Text('Tolak undangan'),
          ),
        ],
      ),
    );
  }
}

/// Names a household. Reached either from onboarding, where it creates one, or
/// on resume when an older account still carries a generated name.
class HouseholdSetupScreen extends StatefulWidget {
  const HouseholdSetupScreen({super.key, required this.auth});

  final AuthRepository auth;

  @override
  State<HouseholdSetupScreen> createState() => _HouseholdSetupScreenState();
}

class _HouseholdSetupScreenState extends State<HouseholdSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late String _currency;
  bool _loading = false;
  String? _error;

  /// True when there is no household yet, so submitting creates one.
  late final bool _isCreating;

  @override
  void initState() {
    super.initState();
    final household = widget.auth.session?.household;
    _isCreating = household == null;
    _name = TextEditingController(text: household?.name ?? '');
    _currency = household?.baseCurrency ?? 'IDR';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isCreating) {
        await widget.auth.createHousehold(
          name: _name.text.trim(),
          baseCurrency: _currency,
        );
      } else {
        await widget.auth.completeHouseholdSetup(
          name: _name.text.trim(),
          baseCurrency: _currency,
        );
      }
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeAuthError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.auth.session?.user.displayName ?? '';
    return AuthScaffold(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BrandHeader(),
            const SizedBox(height: 34),
            Text(
              _isCreating
                  ? 'Rumah tangga baru'
                  : name.isEmpty
                  ? 'Satu langkah lagi'
                  : 'Halo, $name',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 10),
            const Text(
              'Beri nama rumah tanggamu. Nama ini yang akan dilihat '
              'anggota keluarga lain saat kamu undang.',
              style: TextStyle(
                color: AppColors.mutedInk,
                fontSize: 16,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.done,
              autofocus: true,
              maxLength: 160,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Nama rumah tangga',
                hintText: 'Keluarga Santoso',
                counterText: '',
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Beri nama rumah tanggamu.'
                  : null,
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Mata uang utama'),
              items: [
                for (final entry in supportedCurrencies.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(
                      '${entry.key}, ${entry.value}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _loading
                  ? null
                  : (value) => setState(() => _currency = value ?? _currency),
            ),
            const SizedBox(height: 8),
            const Text(
              'Semua catatan akan dijumlahkan dalam mata uang ini. '
              'Bisa diubah lagi nanti.',
              style: TextStyle(
                color: AppColors.mutedInk,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 18),
              AuthErrorNote(message: _error!),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Buka catatan rumah'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Both auth screens are entry points with nothing to go back to, so this
/// scaffold has no back affordance.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child});

  final Widget child;

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
              padding: const EdgeInsets.fromLTRB(24, 34, 24, 42),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.auth});

  final AuthRepository auth;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(auth: widget.auth),
          ReviewScreen(auth: widget.auth),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.hairline)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.paleMoss,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          height: 68,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Beranda',
            ),
            // No count on the badge: the review inbox is not loaded yet, and a
            // hardcoded number would be a claim about the user's data.
            NavigationDestination(
              icon: Icon(Icons.fact_check_outlined),
              selectedIcon: Icon(Icons.fact_check),
              label: 'Tinjau',
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.auth});

  final AuthRepository auth;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<Dashboard> _future;
  bool _balanceVisible = true;

  AuthUser? get _user => widget.auth.session?.user;
  HouseholdContext? get _household => widget.auth.session?.household;

  @override
  void initState() {
    super.initState();
    _future = widget.auth.dashboard();
  }

  Future<void> _reload() async {
    final next = widget.auth.dashboard();
    setState(() {
      _future = next;
    });
    // Swallowed here because the FutureBuilder renders the failure; letting it
    // escape would also break the pull-to-refresh spinner.
    await next.then<void>((_) {}).catchError((Object _) {});
  }

  String get _initial {
    final name = _user?.displayName.trim() ?? '';
    return name.isEmpty ? '?' : name.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Household and display names come from user input and
                      // can be long, so both clip instead of pushing the
                      // avatar off a narrow screen.
                      Text(
                        _household?.name ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.quietInk,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Halo, ${_user?.displayName ?? 'keluarga'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: 'Buka profil',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => _showProfileSheet(context, widget.auth),
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.paleMoss,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        _initial,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppColors.forest,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<Dashboard>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const DataStateView(
                    icon: Icons.sync,
                    title: 'Mengambil catatan rumah',
                    message: 'Saldo dan catatan terbaru sedang dimuat.',
                    loading: true,
                  );
                }
                if (snapshot.hasError) {
                  return DataStateView(
                    icon: Icons.cloud_off_outlined,
                    title: 'Catatan belum dapat dimuat',
                    message: describeAuthError(snapshot.error!),
                    actionLabel: 'Coba lagi',
                    onAction: _reload,
                  );
                }
                return _buildReady(snapshot.data!);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReady(Dashboard data) {
    final total = data.total;
    final others = data.otherCurrencies;

    return RefreshIndicator(
      color: AppColors.forest,
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
        children: [
          BalanceCard(
            total: total,
            accountCount: data.accounts.length,
            otherCurrencies: others,
            visible: _balanceVisible,
            onToggle: () => setState(() => _balanceVisible = !_balanceVisible),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: QuickAction(
                  icon: Icons.add,
                  label: 'Catat uang',
                  filled: true,
                  onTap: () async {
                    if (await _showAddTransaction(context, widget.auth)) {
                      await _reload();
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: QuickAction(
                  icon: Icons.swap_horiz,
                  label: 'Pindah dana',
                  onTap: () async {
                    if (await _showTransfer(context, widget.auth)) {
                      await _reload();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          const SectionHeading(title: 'Catatan terbaru'),
          const SizedBox(height: 6),
          if (data.recentTransactions.isEmpty)
            const EmptyLedgerNote()
          else
            for (var i = 0; i < data.recentTransactions.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 58),
              LedgerRow(entry: data.recentTransactions[i]),
            ],
        ],
      ),
    );
  }
}

/// The headline figure. Forest on white so the one number that matters is the
/// darkest thing on the screen; everything else defers to it.
class BalanceCard extends StatelessWidget {
  const BalanceCard({
    super.key,
    required this.total,
    required this.accountCount,
    required this.otherCurrencies,
    required this.visible,
    required this.onToggle,
  });

  final Money total;
  final int accountCount;
  final Map<String, int> otherCurrencies;
  final bool visible;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 12, 20),
      decoration: BoxDecoration(
        color: AppColors.forest,
        borderRadius: BorderRadius.circular(AppRadius.container),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total dana keluarga',
                  style: TextStyle(color: Color(0xFFD8E0D2), fontSize: 13.5),
                ),
              ),
              IconButton(
                tooltip: visible ? 'Sembunyikan saldo' : 'Tampilkan saldo',
                onPressed: onToggle,
                color: AppColors.paper,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  visible
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            visible ? total.format() : total.masked,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              color: Colors.white,
              fontFamily: 'NotoSans',
              fontSize: 32,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            accountCount == 0
                ? 'Belum ada akun'
                : '$accountCount akun tercatat',
            style: const TextStyle(color: Color(0xFFD8E0D2), fontSize: 12.5),
          ),
          // Other currencies are listed rather than folded into the total,
          // because adding them together would invent an exchange rate.
          if (otherCurrencies.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Di luar total: ${otherCurrencies.entries.map((e) => Money(atomic: e.value, currency: e.key).format()).join(' · ')}',
              style: const TextStyle(color: Color(0xFFD8E0D2), fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}

class LedgerRow extends StatelessWidget {
  const LedgerRow({super.key, required this.entry});

  final RecentTransaction entry;

  /// Today and yesterday read as words; anything older needs its date.
  String _when(DateTime at) {
    final now = DateTime.now();
    final day = DateTime(at.year, at.month, at.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    final time =
        '${at.hour.toString().padLeft(2, '0')}.${at.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return 'Hari ini, $time';
    if (diff == 1) return 'Kemarin, $time';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    return '${at.day} ${months[at.month - 1]}, $time';
  }

  @override
  Widget build(BuildContext context) {
    final income = entry.isIncome;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: income ? AppColors.paleMoss : const Color(0xFFF4EFE7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              income ? Icons.south_west : Icons.north_east,
              size: 19,
              color: income ? AppColors.forest : AppColors.mutedInk,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _when(entry.occurredAt),
                  style: const TextStyle(
                    color: AppColors.quietInk,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            entry.amount.format(signed: income, sign: income ? 1 : -1),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
              color: income ? AppColors.forest : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// A first-run ledger is normal, not a failure, so this sits inside the page
/// rather than replacing it: the balance card above still says zero honestly.
class EmptyLedgerNote extends StatelessWidget {
  const EmptyLedgerNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.hairline),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Belum ada catatan',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          SizedBox(height: 5),
          Text(
            'Catatan pertama akan muncul di sini setelah kamu menambahkannya.',
            style: TextStyle(
              color: AppColors.mutedInk,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.auth});

  final AuthRepository auth;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late Future<CandidateList> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.auth.candidates();
  }

  Future<void> _reload() async {
    final next = widget.auth.candidates();
    setState(() {
      _future = next;
    });
    await next.then<void>((_) {}).catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
            child: Text(
              'Tinjau dulu',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 0, 22, 0),
            child: Text(
              'Email hanya menjadi usulan. Kamu yang memutuskan apa yang '
              'masuk ke catatan.',
              style: TextStyle(
                color: AppColors.mutedInk,
                height: 1.5,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<CandidateList>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const DataStateView(
                    icon: Icons.mark_email_read_outlined,
                    title: 'Memeriksa email transaksi',
                    message:
                        'Rumpun sedang mengambil usulan yang cocok '
                        'dengan aturan emailmu.',
                    loading: true,
                  );
                }
                if (snapshot.hasError) {
                  return DataStateView(
                    icon: Icons.sync_problem_outlined,
                    title: 'Email belum dapat diperiksa',
                    message: describeAuthError(snapshot.error!),
                    actionLabel: 'Coba lagi',
                    onAction: _reload,
                  );
                }
                final items = snapshot.data!.items;
                if (items.isEmpty) {
                  return DataStateView(
                    icon: Icons.done_all,
                    title: 'Tidak ada yang menunggu',
                    message:
                        'Usulan dari email akan muncul di sini setelah '
                        'Gmail terhubung dan ada transaksi yang cocok.',
                    actionLabel: 'Muat ulang',
                    onAction: _reload,
                  );
                }
                return RefreshIndicator(
                  color: AppColors.forest,
                  onRefresh: _reload,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => CandidateCard(
                      auth: widget.auth,
                      candidate: items[index],
                      onDone: _reload,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One proposed transaction. Confirm and reject are on the card because the
/// decision is usually obvious from the amount and the name; nothing here
/// touches the ledger until one of them is pressed.
class CandidateCard extends StatefulWidget {
  const CandidateCard({
    super.key,
    required this.auth,
    required this.candidate,
    required this.onDone,
  });

  final AuthRepository auth;
  final Candidate candidate;
  final Future<void> Function() onDone;

  @override
  State<CandidateCard> createState() => _CandidateCardState();
}

class _CandidateCardState extends State<CandidateCard> {
  bool _busy = false;
  String? _error;

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await widget.onDone();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeAuthError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.candidate;
    final auth = widget.auth;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.container),
        border: Border.all(
          color: c.needsInput ? AppColors.clay : AppColors.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  c.description ?? 'Tanpa keterangan',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // The unread-amount placeholder is far longer than a number, so
              // it has to be allowed to shrink like the description does.
              Flexible(
                child: Text(
                  c.amount?.format() ?? 'Jumlah belum terbaca',
                  maxLines: 2,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: c.amount == null ? 13 : 15.5,
                    color: c.amount == null ? AppColors.clay : AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            c.needsInput
                ? 'Perlu dilengkapi sebelum bisa dikonfirmasi'
                : 'Dari email transaksi',
            style: TextStyle(
              fontSize: 12.5,
              color: c.needsInput ? AppColors.clay : AppColors.quietInk,
              fontWeight: c.needsInput ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            AuthErrorNote(message: _error!),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy || c.needsInput
                      ? null
                      : () =>
                            _act(() => auth.confirmCandidate(c.id, c.version)),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Masukkan ke catatan',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              ),
              const SizedBox(width: 8),
              // Fixed-width so a long confirm label cannot squeeze it out of
              // the row on a narrow phone.
              SizedBox(
                width: 72,
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => _act(() => auth.rejectCandidate(c.id, c.version)),
                  child: const Text('Tolak'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
                child: Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
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
                  color: AppColors.paleMoss,
                  shape: BoxShape.circle,
                ),
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(23),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.forest,
                        ),
                      )
                    : Icon(icon, color: AppColors.forest, size: 32),
              ),
              const SizedBox(height: 22),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
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

/// Recording money and moving it between accounts.
///
/// Both forms need the household's accounts before they can be used, so they
/// load first and say why if that fails, rather than opening an empty picker.
Future<bool> _showAddTransaction(
  BuildContext context,
  AuthRepository auth,
) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => MoneySheet(auth: auth),
  );
  return saved ?? false;
}

Future<bool> _showTransfer(BuildContext context, AuthRepository auth) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => TransferSheet(auth: auth),
  );
  return saved ?? false;
}

/// Digits only, formatted as the user types, because an amount typed as
/// "286500" is much easier to check when it reads "286.500".
class ThousandsFormatter extends TextInputFormatter {
  const ThousandsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return newValue.copyWith(text: '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

int? parseAmountInput(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return int.tryParse(digits);
}

class MoneySheet extends StatefulWidget {
  const MoneySheet({super.key, required this.auth});

  final AuthRepository auth;

  @override
  State<MoneySheet> createState() => _MoneySheetState();
}

class _MoneySheetState extends State<MoneySheet> {
  final _form = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  late Future<List<LedgerAccount>> _accounts;
  String? _accountId;
  String _type = 'expense';
  bool _saving = false;
  String? _error;

  /// Generated once per sheet, not per attempt: a retry after a timeout must
  /// carry the same key or the money posts twice.
  final String _idempotencyKey = 'tx-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _accounts = widget.auth.accounts();
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_accountId == null) {
      setState(() => _error = 'Pilih dulu akunnya.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.auth.createTransaction(
        accountId: _accountId!,
        transactionType: _type,
        amountAtomic: parseAmountInput(_amount.text)!,
        description: _description.text.trim(),
        idempotencyKey: _idempotencyKey,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeAuthError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 22, 22, 24 + bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Catat uang',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 18),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('Keluar')),
                  ButtonSegment(value: 'income', label: Text('Masuk')),
                ],
                selected: {_type},
                onSelectionChanged: (value) =>
                    setState(() => _type = value.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: const [ThousandsFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Jumlah',
                  prefixText: 'Rp ',
                ),
                validator: (value) {
                  final parsed = parseAmountInput(value ?? '');
                  if (parsed == null || parsed <= 0) {
                    return 'Isi jumlahnya.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Keperluan'),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Tulis keperluannya.' : null,
              ),
              const SizedBox(height: 14),
              FutureBuilder<List<LedgerAccount>>(
                future: _accounts,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const LinearProgressIndicator(
                      color: AppColors.forest,
                    );
                  }
                  if (snapshot.hasError) {
                    return AuthErrorNote(
                      message: describeAuthError(snapshot.error!),
                    );
                  }
                  final accounts = snapshot.data ?? const <LedgerAccount>[];
                  if (accounts.isEmpty) {
                    return const AuthErrorNote(
                      message:
                          'Belum ada akun untuk dicatat. Tambahkan akun '
                          'dulu di rumah tanggamu.',
                    );
                  }
                  _accountId ??= accounts.first.id;
                  return DropdownButtonFormField<String>(
                    initialValue: _accountId,
                    decoration: const InputDecoration(labelText: 'Dari akun'),
                    items: [
                      for (final account in accounts)
                        DropdownMenuItem(
                          value: account.id,
                          child: Text(
                            account.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => _accountId = value),
                  );
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                AuthErrorNote(message: _error!),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Simpan catatan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TransferSheet extends StatefulWidget {
  const TransferSheet({super.key, required this.auth});

  final AuthRepository auth;

  @override
  State<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<TransferSheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController(text: 'Pindah dana');
  late Future<List<LedgerAccount>> _accounts;
  String? _from;
  String? _to;
  bool _saving = false;
  String? _error;

  final String _idempotencyKey = 'xf-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _accounts = widget.auth.accounts();
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_from == null || _to == null) return;
    if (_from == _to) {
      setState(() => _error = 'Pilih dua akun yang berbeda.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.auth.createTransfer(
        fromAccountId: _from!,
        toAccountId: _to!,
        amountAtomic: parseAmountInput(_amount.text)!,
        description: _description.text.trim(),
        idempotencyKey: _idempotencyKey,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeAuthError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 22, 22, 24 + bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pindah dana',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                'Total uang rumah tidak berubah, hanya pindah tempat.',
                style: TextStyle(
                  color: AppColors.mutedInk,
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              FutureBuilder<List<LedgerAccount>>(
                future: _accounts,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const LinearProgressIndicator(
                      color: AppColors.forest,
                    );
                  }
                  if (snapshot.hasError) {
                    return AuthErrorNote(
                      message: describeAuthError(snapshot.error!),
                    );
                  }
                  final accounts = snapshot.data ?? const <LedgerAccount>[];
                  // A transfer needs somewhere to go, so one account is not
                  // enough and saying so beats an unusable form.
                  if (accounts.length < 2) {
                    return const AuthErrorNote(
                      message:
                          'Pindah dana butuh dua akun. Tambahkan satu '
                          'akun lagi dulu.',
                    );
                  }
                  _from ??= accounts.first.id;
                  _to ??= accounts[1].id;
                  return Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _from,
                        decoration: const InputDecoration(labelText: 'Dari'),
                        items: [
                          for (final a in accounts)
                            DropdownMenuItem(
                              value: a.id,
                              child: Text(
                                a.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() => _from = value),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: _to,
                        decoration: const InputDecoration(labelText: 'Ke'),
                        items: [
                          for (final a in accounts)
                            DropdownMenuItem(
                              value: a.id,
                              child: Text(
                                a.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() => _to = value),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: const [ThousandsFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Jumlah',
                  prefixText: 'Rp ',
                ),
                validator: (value) {
                  final parsed = parseAmountInput(value ?? '');
                  if (parsed == null || parsed <= 0) return 'Isi jumlahnya.';
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                AuthErrorNote(message: _error!),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Pindahkan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showProfileSheet(
  BuildContext context,
  AuthRepository auth,
) async {
  final user = auth.session?.user;
  final household = auth.session?.household;
  final name = user?.displayName.trim() ?? '';
  final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();

  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: AppColors.cream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    // Scrollable because a long name plus the actions can exceed a short
    // screen once the system bars are accounted for.
    builder: (sheetContext) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.paleClay,
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Profil' : name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      user?.email ?? '',
                      style: const TextStyle(
                        color: AppColors.mutedInk,
                        fontSize: 13.5,
                      ),
                    ),
                    if (household != null)
                      Text(
                        '${roleLabels[household.role] ?? household.role}'
                        ' di ${household.name}',
                        style: const TextStyle(color: AppColors.mutedInk),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(sheetContext);
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => PeopleScreen(auth: auth),
                ),
              );
            },
            icon: const Icon(Icons.group_outlined),
            label: const Text('Anggota rumah'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(sheetContext);
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => EmailSetupScreen(auth: auth),
                ),
              );
            },
            icon: const Icon(Icons.mark_email_read_outlined),
            label: const Text('Catatan dari email'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              final navigator = Navigator.of(context);
              Navigator.pop(sheetContext);
              await auth.signOut();
              navigator.pushNamedAndRemoveUntil('/login', (_) => false);
            },
            icon: const Icon(Icons.logout),
            label: const Text('Keluar dari akun'),
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
        Rect.fromCenter(center: Offset.zero, width: 36, height: 17),
        leaf,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant BranchPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

class MiniBranchPainter extends CustomPainter {
  const MiniBranchPainter({this.scale = 1});

  /// The path was drawn against a 42px tile; scaling keeps one source of truth
  /// instead of a second hand-drawn path for the large splash mark.
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
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
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MiniBranchPainter oldDelegate) =>
      oldDelegate.scale != scale;
}

/// The Google "G" in its four brand colors. Google's sign-in branding rules
/// require their own mark, so it cannot be substituted with a Material icon or
/// a plain letter.
class GoogleMarkPainter extends CustomPainter {
  const GoogleMarkPainter();

  /// The official mark, traced from Google's 48x48 SVG so the geometry and the
  /// four brand colors are theirs, not an approximation. Their sign-in
  /// branding rules do not allow a redrawn or recolored G.
  static const _viewBox = 48.0;

  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  /// The standard 48x48 mark. Each color is one closed subpath.
  static final _paths = <Color, String>{
    // The bar of the G sweeps back to the left, so the counter stays open.
    _blue:
        'M45.12 24.5c0-1.56-.14-3.06-.4-4.5H24v8.51h11.84'
        'c-.51 2.75-2.06 5.08-4.39 6.64v5.52h7.11'
        'c4.16-3.83 6.56-9.47 6.56-16.17z',
    _green:
        'M24 46c5.94 0 10.92-1.97 14.56-5.33l-7.11-5.52'
        'c-1.97 1.32-4.49 2.1-7.45 2.1-5.73 0-10.58-3.87-12.31-9.07'
        'H4.34v5.7C7.96 41.07 15.4 46 24 46z',
    _yellow:
        'M11.69 28.18C11.25 26.86 11 25.45 11 24s.25-2.86.69-4.18'
        'v-5.7H4.34C2.85 17.09 2 20.45 2 24s.85 6.91 2.34 9.88'
        'l7.35-5.7z',
    _red:
        'M24 10.75c3.23 0 6.13 1.11 8.41 3.29l6.31-6.31'
        'C34.91 4.18 29.93 2 24 2 15.4 2 7.96 6.93 4.34 14.12'
        'l7.35 5.7c1.73-5.2 6.58-9.07 12.31-9.07z',
  };

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _viewBox, size.height / _viewBox);
    for (final entry in _paths.entries) {
      canvas.drawPath(
        parseSvgPath(entry.value),
        Paint()
          ..color = entry.key
          ..isAntiAlias = true,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(GoogleMarkPainter oldDelegate) => false;
}

/// Minimal SVG path reader: the subset the Google mark uses (M, L, H, V, C, S,
/// Z and their relative forms). Small enough to keep the logo exact without
/// taking a dependency for one asset.
Path parseSvgPath(String d) {
  final path = Path();
  final tokens = RegExp(
    r'([MmCcLlHhVvZzSs])|(-?\d*\.?\d+(?:e-?\d+)?)',
  ).allMatches(d).toList();
  var i = 0;
  var cmd = '';
  double cx = 0, cy = 0, sx = 0, sy = 0;
  // Reflection point for a smooth curve: the mirror of the previous control.
  double px = 0, py = 0;

  double num() => double.parse(tokens[i++].group(0)!);
  bool isCommand() => tokens[i].group(1) != null;

  while (i < tokens.length) {
    if (isCommand()) cmd = tokens[i++].group(1)!;
    switch (cmd) {
      case 'M':
      case 'm':
        final x = num(), y = num();
        cx = cmd == 'M' ? x : cx + x;
        cy = cmd == 'M' ? y : cy + y;
        sx = cx;
        sy = cy;
        path.moveTo(cx, cy);
        // A second coordinate pair after M is an implicit lineto.
        cmd = cmd == 'M' ? 'L' : 'l';
      case 'L':
      case 'l':
        final x = num(), y = num();
        cx = cmd == 'L' ? x : cx + x;
        cy = cmd == 'L' ? y : cy + y;
        path.lineTo(cx, cy);
      case 'H':
      case 'h':
        final x = num();
        cx = cmd == 'H' ? x : cx + x;
        path.lineTo(cx, cy);
      case 'V':
      case 'v':
        final y = num();
        cy = cmd == 'V' ? y : cy + y;
        path.lineTo(cx, cy);
      case 'C':
      case 'c':
        final rel = cmd == 'c';
        final x1 = num() + (rel ? cx : 0), y1 = num() + (rel ? cy : 0);
        final x2 = num() + (rel ? cx : 0), y2 = num() + (rel ? cy : 0);
        final x = num() + (rel ? cx : 0), y = num() + (rel ? cy : 0);
        path.cubicTo(x1, y1, x2, y2, x, y);
        px = x2;
        py = y2;
        cx = x;
        cy = y;
      case 'S':
      case 's':
        final rel = cmd == 's';
        final x1 = 2 * cx - px, y1 = 2 * cy - py;
        final x2 = num() + (rel ? cx : 0), y2 = num() + (rel ? cy : 0);
        final x = num() + (rel ? cx : 0), y = num() + (rel ? cy : 0);
        path.cubicTo(x1, y1, x2, y2, x, y);
        px = x2;
        py = y2;
        cx = x;
        cy = y;
      case 'Z':
      case 'z':
        path.close();
        cx = sx;
        cy = sy;
      default:
        throw FormatException('Unsupported SVG path command: $cmd');
    }
  }
  return path;
}

/// Who is in the household, and who has been invited but not answered.
/// Managers can invite and withdraw; everyone else sees the roster read-only.
/// Setting up email forwarding.
///
/// Gmail cannot be configured from here: creating a forwarding rule needs a
/// restricted OAuth scope and Google verification. So this screen's job is to
/// make the manual steps as short as possible, and to show the confirmation
/// code when Gmail sends it.
class EmailSetupScreen extends StatefulWidget {
  const EmailSetupScreen({super.key, required this.auth});

  final AuthRepository auth;

  @override
  State<EmailSetupScreen> createState() => _EmailSetupScreenState();
}

class _EmailSetupScreenState extends State<EmailSetupScreen> {
  late Future<InboxAddress?> _future;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = widget.auth.inboxAddress();
  }

  Future<void> _reload() async {
    final next = widget.auth.inboxAddress();
    setState(() {
      _future = next;
    });
    await next.then<void>((_) {}).catchError((Object _) {});
  }

  Future<void> _create() async {
    if (_creating) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      await widget.auth.createInboxAddress();
      await _reload();
      if (mounted) setState(() => _creating = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = describeAuthError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = widget.auth.session?.household?.canEdit ?? false;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Catatan dari email'),
      ),
      body: FutureBuilder<InboxAddress?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const DataStateView(
              icon: Icons.mark_email_read_outlined,
              title: 'Membuka pengaturan',
              message: 'Sedang mengambil alamat rumahmu.',
              loading: true,
            );
          }
          if (snapshot.hasError) {
            return DataStateView(
              icon: Icons.cloud_off_outlined,
              title: 'Pengaturan belum dapat dibuka',
              message: describeAuthError(snapshot.error!),
              actionLabel: 'Coba lagi',
              onAction: _reload,
            );
          }
          final address = snapshot.data;
          if (address == null) {
            return _Intro(
              canManage: canManage,
              creating: _creating,
              error: _error,
              onCreate: _create,
            );
          }
          return _Steps(address: address, onRefresh: _reload);
        },
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({
    required this.canManage,
    required this.creating,
    required this.error,
    required this.onCreate,
  });

  final bool canManage;
  final bool creating;
  final String? error;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
      children: [
        Text(
          'Biar email bank jadi catatan',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 10),
        const Text(
          'Rumpun memberi rumahmu satu alamat email rahasia. Teruskan email '
          'transaksi dari bank ke alamat itu, dan Rumpun akan menyiapkan '
          'usulan catatan untuk kamu periksa.',
          style: TextStyle(
            color: AppColors.mutedInk,
            height: 1.55,
            fontSize: 14.5,
          ),
        ),
        const SizedBox(height: 18),
        // Said plainly: the app never reads the mailbox, and that is a
        // deliberate limit, not a missing feature.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: AppColors.hairline),
          ),
          child: const Text(
            'Rumpun tidak pernah membuka kotak masukmu. Yang sampai ke '
            'Rumpun hanya email yang kamu teruskan sendiri.',
            style: TextStyle(fontSize: 13.5, height: 1.5),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          AuthErrorNote(message: error!),
        ],
        const SizedBox(height: 22),
        if (canManage)
          FilledButton(
            onPressed: creating ? null : onCreate,
            child: creating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Buat alamat rumah'),
          )
        else
          const AuthErrorNote(
            message: 'Hanya pemilik atau admin rumah yang bisa menyiapkan ini.',
          ),
      ],
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.address, required this.onRefresh});

  final InboxAddress address;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.forest,
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
        children: [
          if (address.isActive)
            _Banner(
              icon: Icons.check_circle_outline,
              tone: AppColors.forest,
              title: 'Sudah jalan',
              body: address.messageCount == 1
                  ? '1 email sudah diterima.'
                  : '${address.messageCount} email sudah diterima.',
            )
          else
            const _Banner(
              icon: Icons.schedule,
              tone: AppColors.clay,
              title: 'Menunggu email pertama',
              body: 'Selesaikan langkah di bawah, lalu tunggu sebentar.',
            ),
          const SizedBox(height: 20),
          const _StepTitle(number: 1, title: 'Salin alamat rumahmu'),
          const SizedBox(height: 8),
          _CopyRow(value: address.address),
          const SizedBox(height: 22),
          const _StepTitle(
            number: 2,
            title: 'Tambahkan di Gmail sebagai alamat penerusan',
          ),
          const SizedBox(height: 8),
          const Text(
            'Buka Gmail di browser: Setelan, lalu Penerusan dan POP/IMAP, '
            'lalu Tambahkan alamat penerusan. Tempel alamat tadi.',
            style: TextStyle(
              color: AppColors.mutedInk,
              height: 1.55,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 22),
          const _StepTitle(number: 3, title: 'Masukkan kode dari Gmail'),
          const SizedBox(height: 8),
          if (address.verificationCode != null) ...[
            const Text(
              'Gmail sudah mengirim kodenya ke Rumpun. Tempel kode ini di '
              'halaman Gmail tadi:',
              style: TextStyle(
                color: AppColors.mutedInk,
                height: 1.55,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 10),
            _CopyRow(value: address.verificationCode!, large: true),
          ] else
            const Text(
              'Gmail akan mengirim kode ke alamat tadi. Kodenya akan muncul '
              'di sini, tarik layar ke bawah untuk memeriksa.',
              style: TextStyle(
                color: AppColors.mutedInk,
                height: 1.55,
                fontSize: 14,
              ),
            ),
          const SizedBox(height: 22),
          const _StepTitle(number: 4, title: 'Buat filter untuk email bank'),
          const SizedBox(height: 8),
          const Text(
            'Di Gmail: Setelan, lalu Filter, lalu Buat filter baru. Isi '
            'kolom Dari dengan alamat bankmu, lalu pilih Teruskan ke alamat '
            'Rumpun.',
            style: TextStyle(
              color: AppColors.mutedInk,
              height: 1.55,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          const _CopyRow(
            value: 'from:(bca.co.id OR bankmandiri.co.id OR gopay.co.id)',
            small: true,
          ),
          const SizedBox(height: 26),
          Text(
            'Kenapa harus manual? Untuk mengatur Gmail dari dalam aplikasi, '
            'Rumpun perlu izin membaca seluruh kotak masukmu. Rumpun memilih '
            'tidak meminta izin itu.',
            style: TextStyle(
              color: AppColors.quietInk,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: tone),
      ),
      child: Row(
        children: [
          Icon(icon, color: tone, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppColors.mutedInk,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.number, required this.title});

  final int number;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.paleMoss,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppColors.forest,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// A value plus a copy button, because every one of these has to be pasted
/// into Gmail and retyping an address by hand invites a typo.
class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.value, this.large = false, this.small = false});

  final String value;
  final bool large;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5F0),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            // An email address broken mid-word ("...rumpun.ap / p") reads as
            // two addresses. Shrinking to fit keeps it one line and one thing.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SelectableText(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: large ? 20 : (small ? 12.5 : 14),
                  fontWeight: large ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: large ? 1.5 : 0,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Salin',
            icon: const Icon(Icons.copy_rounded, size: 19),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Tersalin.')));
            },
          ),
        ],
      ),
    );
  }
}

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key, required this.auth});

  final AuthRepository auth;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  late Future<HouseholdPeople> _people;

  @override
  void initState() {
    super.initState();
    _people = widget.auth.people();
  }

  void _reload() {
    setState(() {
      _people = widget.auth.people();
    });
  }

  bool get _canManage => widget.auth.session?.household?.canEdit ?? false;

  Future<void> _invite() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => InviteSheet(auth: widget.auth),
    );
    if (sent ?? false) _reload();
  }

  Future<void> _revoke(PendingInvite invite) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.auth.revokeInvite(invite.id);
      _reload();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeAuthError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final household = widget.auth.session?.household;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Anggota rumah'),
        backgroundColor: AppColors.paper,
        surfaceTintColor: Colors.transparent,
      ),
      body: FutureBuilder<HouseholdPeople>(
        future: _people,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const DataStateView(
              icon: Icons.group_outlined,
              loading: true,
              title: 'Mengambil daftar anggota',
              message: 'Sebentar ya.',
            );
          }
          if (snapshot.hasError) {
            return DataStateView(
              icon: Icons.cloud_off_outlined,
              title: 'Daftar anggota belum bisa dibuka',
              message: describeAuthError(snapshot.error!),
              actionLabel: 'Coba lagi',
              onAction: _reload,
            );
          }

          final people = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              if (household != null)
                Text(
                  household.name,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              const SizedBox(height: 18),
              for (final member in people.members)
                PersonRow(
                  title: member.isYou
                      ? '${member.displayName} (kamu)'
                      : member.displayName,
                  subtitle: member.email,
                  trailing: roleLabels[member.role] ?? member.role,
                ),
              if (people.invites.isNotEmpty) ...[
                const SizedBox(height: 26),
                const SectionHeading(title: 'Menunggu jawaban'),
                const SizedBox(height: 8),
                for (final invite in people.invites)
                  PersonRow(
                    title: invite.email,
                    subtitle:
                        'Diundang sebagai ${roleLabels[invite.role] ?? invite.role}',
                    onRemove: () => _revoke(invite),
                  ),
              ],
              if (_canManage) ...[
                const SizedBox(height: 26),
                FilledButton.icon(
                  onPressed: _invite,
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Undang lewat email'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class PersonRow extends StatelessWidget {
  const PersonRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onRemove,
  });

  final String title;
  final String subtitle;
  final String? trailing;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.mutedInk,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                trailing!,
                style: const TextStyle(
                  color: AppColors.mutedInk,
                  fontSize: 13.5,
                ),
              ),
            ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Tarik undangan',
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 20),
            ),
        ],
      ),
    );
  }
}

/// Collects an email and a role. Roles are explained in plain words, because
/// "viewer" and "member" mean nothing to someone adding their spouse.
class InviteSheet extends StatefulWidget {
  const InviteSheet({super.key, required this.auth});

  final AuthRepository auth;

  @override
  State<InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<InviteSheet> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  String _role = 'member';
  bool _loading = false;
  String? _error;

  static const _roleHelp = <String, String>{
    'admin': 'Bisa mencatat, mengubah, dan mengundang anggota lain.',
    'member': 'Bisa mencatat dan mengubah transaksi.',
    'viewer': 'Hanya bisa melihat catatan.',
    'child': 'Hanya bisa melihat, cocok untuk anak.',
  };

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.auth.invite(email: _email.text.trim(), role: _role);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeAuthError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        24,
        22,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Undang anggota',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Mereka akan melihat undangan ini saat masuk dengan akun '
              'Google yang memakai email tersebut.',
              style: TextStyle(
                color: AppColors.mutedInk,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Email anggota',
                hintText: 'nama@gmail.com',
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty || !text.contains('@') || text.endsWith('@')) {
                  return 'Masukkan alamat email yang valid.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _role,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Peran'),
              items: [
                for (final entry in _roleHelp.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(
                      roleLabels[entry.key] ?? entry.key,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _loading
                  ? null
                  : (value) => setState(() => _role = value ?? _role),
            ),
            const SizedBox(height: 8),
            Text(
              _roleHelp[_role] ?? '',
              style: const TextStyle(
                color: AppColors.mutedInk,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 18),
              AuthErrorNote(message: _error!),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Kirim undangan'),
            ),
          ],
        ),
      ),
    );
  }
}
