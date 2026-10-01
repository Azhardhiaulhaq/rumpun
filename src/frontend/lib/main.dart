import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'api/auth_repository.dart';
import 'api/models.dart';
import 'ledger_screen.dart';
import 'category_screen.dart';
import 'gmail_connect_screen.dart';
import 'push_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var pushEnabled = false;
  try {
    await Firebase.initializeApp();
    pushEnabled = true;
  } catch (error) {
    debugPrint('Firebase setup unavailable: ${error.runtimeType}');
  }
  runApp(
    RumpunApp(
      auth: AuthRepository(),
      gmailReturnLinks: AppLinks().uriLinkStream,
      pushEnabled: pushEnabled,
    ),
  );
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
      case 'candidate_account_required':
        return 'Pilih dulu akun yang membayar.';
      case 'candidate_incomplete':
        return 'Usulan ini belum lengkap. Periksa jumlah dan tanggalnya.';
      case 'candidate_version_conflict':
      case 'candidate_state_conflict':
        return 'Usulan ini baru saja berubah. Muat ulang lalu coba lagi.';
      case 'candidate_already_confirmed':
      case 'candidate_confirmation_conflict':
        return 'Usulan ini sudah masuk ke catatan.';
      case 'candidate_direction_unsupported':
        return 'Hanya pengeluaran yang bisa dicatat langsung dari email.';
      case 'invalid_candidate_account':
        return 'Akun itu tidak bisa dipakai untuk usulan ini.';
      case 'invalid_category':
        return 'Kategori itu tidak cocok untuk pengeluaran.';
      case 'category_required':
        return 'Tambahkan kategori pengeluaran dulu.';
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

class RumpunApp extends StatefulWidget {
  const RumpunApp({
    super.key,
    required this.auth,
    this.gmailReturnLinks,
    this.pushEnabled = false,
  });

  final AuthRepository auth;

  /// A supplied stream keeps navigation testable without a platform channel.
  final Stream<Uri>? gmailReturnLinks;
  final bool pushEnabled;

  @override
  State<RumpunApp> createState() => _RumpunAppState();
}

class _RumpunAppState extends State<RumpunApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final NavigatorObserver _navigationObserver = _GmailReturnObserver(
    _onRouteChanged,
  );
  StreamSubscription<Uri>? _linkSubscription;
  PushNotifications? _push;
  String? _currentRoute;
  bool _pendingGmailReturn = false;
  bool _navigationScheduled = false;

  @override
  void initState() {
    super.initState();
    // The stream includes cold-start links. Subscribe before the splash screen
    // restores the session so an OAuth return cannot be lost during startup.
    _linkSubscription = widget.gmailReturnLinks?.listen(_onLink);
    if (widget.pushEnabled) {
      _push = PushNotifications(
        widget.auth,
        onReview: () {
          if (widget.auth.isSignedIn) {
            _navigatorKey.currentState?.pushNamed('/review');
          }
        },
        onForeground: (RemoteMessage message) {
          final context = _navigatorKey.currentContext;
          if (context == null || !widget.auth.isSignedIn) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                message.notification?.body ?? 'Ada kabar baru dari Rumpun.',
              ),
              action: SnackBarAction(
                label: 'Lihat',
                onPressed: () {
                  _navigatorKey.currentState?.pushNamed('/review');
                },
              ),
            ),
          );
        },
      );
    }
  }

  @override
  void dispose() {
    _push?.dispose();
    _linkSubscription?.cancel();
    super.dispose();
  }

  void _onLink(Uri uri) {
    if (uri.scheme != 'rumpun' ||
        (uri.host != 'gmail-connected' && uri.host != 'gmail-cancelled')) {
      return;
    }
    _pendingGmailReturn = true;
    _openPendingGmail();
  }

  void _onRouteChanged(String? route) {
    _currentRoute = route;
    _openPendingGmail();
  }

  void _openPendingGmail() {
    if (!_pendingGmailReturn || _navigationScheduled) return;
    _navigationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigationScheduled = false;
      if (!mounted || !_pendingGmailReturn || !widget.auth.isSignedIn) return;
      if (_currentRoute == null ||
          const {
            '/',
            '/login',
            '/onboarding',
            '/setup',
          }.contains(_currentRoute)) {
        return;
      }
      final navigator = _navigatorKey.currentState;
      if (navigator == null) return;
      _pendingGmailReturn = false;
      if (_currentRoute == '/gmail') {
        navigator.pushReplacementNamed('/gmail');
      } else {
        navigator.pushNamed('/gmail');
      }
    });
  }

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
      navigatorKey: _navigatorKey,
      navigatorObservers: [_navigationObserver],
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
        '/': (_) => SplashScreen(auth: widget.auth),
        '/login': (_) => LoginScreen(auth: widget.auth),
        '/onboarding': (_) => OnboardingScreen(auth: widget.auth),
        '/setup': (_) => HouseholdSetupScreen(auth: widget.auth),
        '/home': (_) => AppShell(auth: widget.auth),
        '/gmail': (_) => GmailConnectScreen(auth: widget.auth),
        '/review': (_) => AppShell(auth: widget.auth, initialIndex: 1),
      },
    );
  }
}

class _GmailReturnObserver extends NavigatorObserver {
  _GmailReturnObserver(this.onChanged);

  final void Function(String?) onChanged;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onChanged(route.settings.name);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onChanged(previousRoute?.settings.name);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    onChanged(newRoute?.settings.name);
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

  /// Clay darkened for small text on [paleClay]. The clay used for buttons is
  /// 4.28:1 there, under the 4.5:1 bar, and the change pills set 12.5px text
  /// on that ground.
  static const deepClay = Color(0xFF8A3D21);

  /// 4.53:1 on white. The lightest ink allowed to carry normal-size text.
  static const quietInk = Color(0xFF747775);

  /// The navigation bar is one solid block of forest, so its own tokens live
  /// here rather than being mixed in with the on-white palette.
  ///
  /// Forest is already dark, so no darker shade can reach 3:1 against it:
  /// [navActive] tops out near 1.8:1 and is a supporting cue, not the signal.
  /// The state is carried by the label (white and bold against [navIdle] at
  /// 5.65:1) and by the filled icon, so the tab is still readable to anyone
  /// who cannot separate two greens.
  static const navActive = Color(0xFF0A1C11);
  static const navIdle = Color(0xFFB9C9B2);

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
  const AppShell({super.key, required this.auth, this.initialIndex = 0});

  final AuthRepository auth;
  final int initialIndex;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index = widget.initialIndex;

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
      bottomNavigationBar: RumpunNavBar(
        index: _index,
        onSelect: (value) => setState(() => _index = value),
      ),
    );
  }
}

/// The app's own bottom bar rather than Material's NavigationBar.
///
/// On a dark bar the stock component fights back: its indicator pill is sized
/// for a light surface, its ripple washes the forest out, and the label sits
/// too far from the icon to read as one target. This draws the two
/// destinations directly, so the active state is a single deliberate shape.
class RumpunNavBar extends StatelessWidget {
  const RumpunNavBar({super.key, required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const _items = [
    (icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Beranda'),
    (
      icon: Icons.fact_check_outlined,
      activeIcon: Icons.fact_check,
      label: 'Tinjau',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.forest,
        // A hairline of deeper forest instead of a shadow: the bar is anchored
        // to the bottom of the screen, so it needs a boundary, not elevation.
        border: Border(top: BorderSide(color: Color(0xFF16311F))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _NavItem(
                    item: _items[i],
                    selected: i == index,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ({IconData icon, IconData activeIcon, String label}) item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Forest is already dark, so no darker shade reaches 3:1 against it. The
    // state is carried by the filled icon and the brightness of the label,
    // which both survive without colour vision.
    final colour = selected ? Colors.white : AppColors.navIdle;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        // Whole cell, so the target is the full half of the bar rather than
        // just the glyph.
        splashColor: Colors.white.withValues(alpha: 0.07),
        highlightColor: Colors.white.withValues(alpha: 0.05),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? item.activeIcon : item.icon,
              size: 23,
              color: colour,
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11.5,
                height: 1,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: colour,
              ),
            ),
            const SizedBox(height: 5),
            // The marker sits under the label as a short rule. A pill behind
            // the icon reads as a button on a dark bar; a rule reads as a tab.
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              height: 2.5,
              width: selected ? 22 : 0,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
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
  final ScrollController _scrollController = ScrollController();
  // The charts load on their own so a slow trends query cannot hold back the
  // balance, which is what people open the app for.
  Future<Trends>? _trends;
  Future<MonthlySpending>? _spending;
  String? _selectedTrendCurrency;
  bool _balanceVisible = true;

  AuthUser? get _user => widget.auth.session?.user;
  HouseholdContext? get _household => widget.auth.session?.household;

  /// The charts sit below the balance, so their FutureBuilder is only mounted
  /// once the dashboard resolves. A trends request that fails before then
  /// would have no listener and surface as an unhandled async error, so the
  /// failure is claimed here while still being left on the future for the
  /// FutureBuilder to render.
  Future<MonthlySpending> _loadSpending() {
    final request = widget.auth.monthlySpending();
    unawaited(request.then<void>((_) {}, onError: (Object _) {}));
    return request;
  }

  Future<Trends> _loadTrends() {
    final request = widget.auth.trends(currency: _selectedTrendCurrency);
    unawaited(request.then<void>((_) {}, onError: (Object _) {}));
    return request;
  }

  @override
  void initState() {
    super.initState();
    _future = widget.auth.dashboard();
    _trends = _loadTrends();
    _spending = _loadSpending();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final next = widget.auth.dashboard();
    final nextTrends = _loadTrends();
    final nextSpending = _loadSpending();
    setState(() {
      _future = next;
      _trends = nextTrends;
      _spending = nextSpending;
    });
    // Swallowed here because the FutureBuilder renders the failure; letting it
    // escape would also break the pull-to-refresh spinner.
    await next.then<void>((_) {}).catchError((Object _) {});
    await nextTrends.then<void>((_) {}).catchError((Object _) {});
    await nextSpending.then<void>((_) {}).catchError((Object _) {});
  }

  void _selectTrendCurrency(String currency) {
    if (currency == (_selectedTrendCurrency ?? _household?.baseCurrency)) {
      return;
    }
    setState(() {
      _selectedTrendCurrency = currency;
      _trends = _loadTrends();
    });
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
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => _showProfileSheet(context, widget.auth),
                    child: Container(
                      // 48, not 44: Android's guideline is the stricter of the
                      // two platforms and this is the same circle on both.
                      width: 48,
                      height: 48,
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
    return RefreshIndicator(
      color: AppColors.forest,
      onRefresh: _reload,
      child: ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
        children: [
          AssetsCarousel(
            dashboard: data,
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
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LedgerScreen(auth: widget.auth),
                ),
              );
              if (mounted) await _reload();
            },
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('Lihat akun dan riwayat'),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CategoryScreen(auth: widget.auth),
                ),
              );
              if (mounted) await _reload();
            },
            icon: const Icon(Icons.category_outlined),
            label: const Text('Atur kategori & anggaran'),
          ),
          const SizedBox(height: 28),
          if (data.currencies.length > 1) ...[
            Text(
              'Mata uang grafik',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final currency in data.currencies)
                  OutlinedButton(
                    key: Key('trend-currency-$currency'),
                    onPressed: () => _selectTrendCurrency(currency),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(72, 44),
                      backgroundColor:
                          currency ==
                              (_selectedTrendCurrency ??
                                  data.household.baseCurrency)
                          ? AppColors.paleMoss
                          : null,
                      foregroundColor: AppColors.forest,
                      side: BorderSide(
                        color:
                            currency ==
                                (_selectedTrendCurrency ??
                                    data.household.baseCurrency)
                            ? AppColors.forest
                            : AppColors.moss,
                      ),
                    ),
                    child: Text(currency),
                  ),
              ],
            ),
            const SizedBox(height: 18),
          ],
          TrendsSection(future: _trends, onRetry: _reload),
          const SizedBox(height: 28),
          CategoryPieSection(future: _spending, onRetry: _reload),
        ],
      ),
    );
  }
}

/// The headline figure. Forest on white so the one number that matters is the
/// darkest thing on the screen; everything else defers to it.
/// The headline figure, one card per currency the household holds.
///
/// Currencies are separate cards rather than one sum, because adding rupiah to
/// Singapore dollars would invent an exchange rate. Swiping is the gesture for
/// "another currency"; tapping opens the accounts behind whichever card is
/// showing in a sheet, so a long list gets its own scroll instead of pushing
/// the rest of the home screen off the bottom.
class AssetsCarousel extends StatefulWidget {
  const AssetsCarousel({
    super.key,
    required this.dashboard,
    required this.visible,
    required this.onToggle,
  });

  final Dashboard dashboard;
  final bool visible;
  final VoidCallback onToggle;

  @override
  State<AssetsCarousel> createState() => _AssetsCarouselState();
}

class _AssetsCarouselState extends State<AssetsCarousel> {
  late final PageController _controller = PageController(
    viewportFraction: 0.92,
  );
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currencies = widget.dashboard.currencies;
    // The page indicator only means something when there is more than one
    // page; a lone dot would be decoration.
    final multiple = currencies.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A fixed height because the cards sit in a horizontal pager, which
        // cannot size itself to the tallest child.
        SizedBox(
          height: 176,
          child: PageView.builder(
            controller: _controller,
            itemCount: currencies.length,
            onPageChanged: (value) => setState(() => _page = value),
            // With one currency there is nothing to swipe to, and a pager that
            // rubber-bands against nothing feels broken.
            physics: multiple
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            itemBuilder: (context, index) {
              final currency = currencies[index];
              final holdings = widget.dashboard.holdingsIn(currency);
              return Padding(
                // The gap belongs between cards, so the first and last sit
                // flush with the screen margin.
                padding: EdgeInsets.only(right: multiple ? 10 : 0),
                child: AssetsCard(
                  total: widget.dashboard.totalIn(currency),
                  holdings: holdings,
                  isBase: currency == widget.dashboard.household.baseCurrency,
                  visible: widget.visible,
                  onToggle: widget.onToggle,
                  onTap: () => showHoldingsSheet(
                    context,
                    currency: currency,
                    total: widget.dashboard.totalIn(currency),
                    holdings: holdings,
                    visible: widget.visible,
                  ),
                ),
              );
            },
          ),
        ),
        if (multiple) ...[
          const SizedBox(height: 12),
          _PageDots(count: currencies.length, active: _page),
        ],
      ],
    );
  }
}

class AssetsCard extends StatelessWidget {
  const AssetsCard({
    super.key,
    required this.total,
    required this.holdings,
    required this.isBase,
    required this.visible,
    required this.onToggle,
    required this.onTap,
  });

  final Money total;
  final List<AccountBalance> holdings;
  final bool isBase;
  final bool visible;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = isBase
        ? 'Total aset keluarga'
        : 'Aset dalam ${total.currency}';
    // Accounts holding nothing are still real accounts, but counting them here
    // overstates what the household has anywhere to look at. The count is the
    // answer to "how many places is this spread across".
    final funded = [
      for (final h in holdings)
        if (h.balance.atomic != 0) h,
    ];

    return Semantics(
      button: true,
      label: '$label, ${visible ? total.format() : 'disembunyikan'}',
      hint: 'Ketuk untuk melihat rincian akun',
      child: Material(
        color: AppColors.forest,
        borderRadius: BorderRadius.circular(AppRadius.container),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              // The identity motif, one continuous branch, sits behind the
              // figure at low contrast. It marks the card as Rumpun's without
              // competing with the number.
              Positioned(
                right: -30,
                bottom: -34,
                width: 200,
                height: 150,
                child: IgnorePointer(
                  child: CustomPaint(painter: CardBranchPainter()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 8, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFD8E0D2),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: visible
                              ? 'Sembunyikan saldo'
                              : 'Tampilkan saldo',
                          onPressed: onToggle,
                          color: AppColors.paper,
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          icon: Icon(
                            visible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 21,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        visible ? total.format() : total.masked,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              color: Colors.white,
                              fontFamily: 'NotoSans',
                              fontSize: 34,
                              letterSpacing: -0.8,
                            ),
                      ),
                    ),
                    const Spacer(),
                    // Reads as the control it is: a row that opens something,
                    // rather than a caption that happens to be tappable.
                    Row(
                      children: [
                        // Flexible, not bare: the household name and the
                        // account count are both variable, and on a 320px
                        // screen the row has to give rather than overflow.
                        Flexible(
                          child: Text(
                            funded.isEmpty
                                ? 'Belum ada akun terisi'
                                : 'Tersebar di ${funded.length} akun',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFD8E0D2),
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.arrow_forward_ios,
                          size: 11,
                          color: Color(0xFFD8E0D2),
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

/// One continuous line joining leaf-shaped nodes: the same motif as the brand
/// mark, drawn large and faint so the card belongs to Rumpun without shouting.
class CardBranchPainter extends CustomPainter {
  const CardBranchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // The branch sweeps along the bottom-right corner rather than across the
    // middle, so it never crosses the figure or the visibility control.
    final branch = Path()
      ..moveTo(size.width * 0.02, size.height * 0.94)
      ..cubicTo(
        size.width * 0.38,
        size.height * 0.92,
        size.width * 0.66,
        size.height * 0.74,
        size.width * 0.86,
        size.height * 0.34,
      );
    canvas.drawPath(branch, stroke);

    // Three leaves along the branch, each a lens shape made of two arcs.
    const stops = [0.34, 0.62, 0.88];
    final metric = branch.computeMetrics().first;
    for (final stop in stops) {
      final at = metric.getTangentForOffset(metric.length * stop);
      if (at == null) continue;
      canvas.save();
      canvas.translate(at.position.dx, at.position.dy);
      canvas.rotate(at.angle);
      final leaf = Path()
        ..moveTo(-13, 0)
        ..quadraticBezierTo(0, -9, 13, 0)
        ..quadraticBezierTo(0, 9, -13, 0)
        ..close();
      canvas.drawPath(
        leaf,
        Paint()..color = Colors.white.withValues(alpha: 0.07),
      );
      canvas.drawPath(leaf, stroke);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(CardBranchPainter oldDelegate) => false;
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: i == active ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == active ? AppColors.forest : AppColors.paleMoss,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ],
    );
  }
}

/// The accounts behind one currency's total.
///
/// A sheet rather than an inline list: twenty accounts expanded in place push
/// the charts off the screen and leave no way back except scrolling, while a
/// sheet scrolls on its own and closes with a swipe or Escape.
Future<void> showHoldingsSheet(
  BuildContext context, {
  required String currency,
  required Money total,
  required List<AccountBalance> holdings,
  required bool visible,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: AppColors.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
  ),
  builder: (_) => HoldingsSheet(
    currency: currency,
    total: total,
    holdings: holdings,
    visible: visible,
  ),
);

class HoldingsSheet extends StatelessWidget {
  const HoldingsSheet({
    super.key,
    required this.currency,
    required this.total,
    required this.holdings,
    required this.visible,
  });

  final String currency;
  final Money total;
  final List<AccountBalance> holdings;
  final bool visible;

  /// Grouped by kind so a long list reads as a few kinds of money rather than
  /// twenty unrelated rows. Ordered by what a household reaches for first.
  static const _order = [
    'cash',
    'bank',
    'ewallet',
    'budget_envelope',
    'investment',
    'foreign_currency',
    'physical_asset',
    'credit_card',
    'loan',
    'other',
  ];

  static const _labels = {
    'cash': 'Tunai',
    'bank': 'Rekening bank',
    'ewallet': 'Dompet digital',
    'budget_envelope': 'Pos anggaran',
    'investment': 'Investasi',
    'foreign_currency': 'Mata uang asing',
    'physical_asset': 'Aset fisik',
    'credit_card': 'Kartu kredit',
    'loan': 'Pinjaman',
    'other': 'Lainnya',
  };

  static const _icons = {
    'cash': Icons.payments_outlined,
    'bank': Icons.account_balance_outlined,
    'ewallet': Icons.smartphone_outlined,
    'budget_envelope': Icons.folder_outlined,
    'investment': Icons.trending_up,
    'foreign_currency': Icons.language_outlined,
    'physical_asset': Icons.diamond_outlined,
    'credit_card': Icons.credit_card,
    'loan': Icons.receipt_long_outlined,
    'other': Icons.circle_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<AccountBalance>>{};
    for (final account in holdings) {
      groups.putIfAbsent(account.kind, () => []).add(account);
    }
    final kinds = groups.keys.toList()
      ..sort((a, b) {
        final ai = _order.indexOf(a);
        final bi = _order.indexOf(b);
        return (ai == -1 ? _order.length : ai).compareTo(
          bi == -1 ? _order.length : bi,
        );
      });

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.68,
      maxChildSize: 0.94,
      minChildSize: 0.45,
      builder: (context, scrollController) => Column(
        children: [
          // The grab handle is the affordance for the drag; without it the
          // sheet looks like a screen that arrived from nowhere.
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.hairline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rincian aset',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        visible
                            ? '${total.format()} dalam $currency'
                            : 'Saldo disembunyikan',
                        style: const TextStyle(
                          color: AppColors.mutedInk,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Tutup',
                  onPressed: () => Navigator.of(context).pop(),
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: holdings.isEmpty
                ? const Padding(
                    padding: EdgeInsets.fromLTRB(22, 26, 22, 22),
                    child: Text(
                      'Belum ada akun dalam mata uang ini. Tambahkan lewat '
                      'Catat uang.',
                      style: TextStyle(
                        color: AppColors.mutedInk,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  )
                : ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(22, 6, 22, 28),
                    children: [
                      for (final kind in kinds) ...[
                        _GroupHeader(
                          icon: _icons[kind] ?? Icons.circle_outlined,
                          label: _labels[kind] ?? 'Lainnya',
                          subtotal: Money(
                            atomic: groups[kind]!.fold<int>(
                              0,
                              (sum, a) => sum + a.balance.atomic,
                            ),
                            currency: currency,
                          ),
                          visible: visible,
                        ),
                        for (final account in groups[kind]!)
                          _HoldingRow(account: account, visible: visible),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.icon,
    required this.label,
    required this.subtotal,
    required this.visible,
  });

  final IconData icon;
  final String label;
  final Money subtotal;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.moss),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.mutedInk,
              ),
            ),
          ),
          // The subtotal answers "how much is in this kind", which is the
          // question the grouping invites.
          Text(
            visible ? subtotal.compact : subtotal.masked,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.mutedInk,
            ),
          ),
        ],
      ),
    );
  }
}

class _HoldingRow extends StatelessWidget {
  const _HoldingRow({required this.account, required this.visible});

  final AccountBalance account;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final empty = account.balance.atomic == 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              account.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                // An account holding nothing is still listed, because it
                // exists, but it recedes rather than competing with the ones
                // that hold money.
                color: empty ? AppColors.quietInk : AppColors.ink,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            visible ? account.balance.format() : account.balance.masked,
            style: TextStyle(
              fontSize: 15,
              fontWeight: empty ? FontWeight.w500 : FontWeight.w700,
              // A negative holding is the one number here that needs to be
              // noticed, so it takes the attention accent.
              color: account.balance.atomic < 0
                  ? AppColors.deepClay
                  : (empty ? AppColors.quietInk : AppColors.ink),
            ),
          ),
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

/// The two questions the home screen answers about time: where the money went
/// this week, and whether the household is holding more than it was.
///
/// Weekly rather than monthly, because this ledger starts in August 2026 and a
/// monthly chart would be two bars, one of them unfinished. Weeks give enough
/// columns to show a shape now; the endpoint takes a granularity so this can
/// move to months once a year of history exists.
class TrendsSection extends StatefulWidget {
  const TrendsSection({super.key, required this.future, required this.onRetry});

  final Future<Trends>? future;
  final Future<void> Function() onRetry;

  @override
  State<TrendsSection> createState() => _TrendsSectionState();
}

class _TrendsSectionState extends State<TrendsSection> {
  Trends? _lastTrends;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Trends>(
      future: widget.future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          final previous = _lastTrends;
          if (previous != null && previous.hasSpending) {
            return Stack(
              children: [
                IgnorePointer(
                  child: Opacity(opacity: 0.35, child: _charts(previous)),
                ),
                const Positioned(
                  top: 2,
                  right: 0,
                  child: Text(
                    'Memuat grafik…',
                    style: TextStyle(
                      color: AppColors.forest,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          }
          return const _TrendsFrame(
            child: SizedBox(
              height: 150,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.forest,
                  ),
                ),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return _TrendsFrame(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    describeAuthError(snapshot.error!),
                    style: const TextStyle(
                      color: AppColors.mutedInk,
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => widget.onRetry(),
                    child: const Text('Muat ulang grafik'),
                  ),
                ],
              ),
            ),
          );
        }

        final trends = snapshot.data!;
        _lastTrends = trends;
        if (!trends.hasSpending) {
          return const _TrendsFrame(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'Grafik muncul setelah ada pengeluaran tercatat. Mulai dari '
                'Catat uang di atas.',
                style: TextStyle(
                  color: AppColors.mutedInk,
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
            ),
          );
        }

        return _charts(trends);
      },
    );
  }

  Widget _charts(Trends trends) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SpendingChart(trends: trends),
      const SizedBox(height: 26),
      NetWorthChart(trends: trends),
    ],
  );
}

class _TrendsFrame extends StatelessWidget {
  const _TrendsFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeading(title: 'Pengeluaran per minggu'),
        child,
      ],
    );
  }
}

/// A change between the last two finished periods.
///
/// Direction is carried by the arrow and the word, not by colour alone, so it
/// still reads for anyone who cannot separate red from green.
class ChangePill extends StatelessWidget {
  const ChangePill({
    super.key,
    required this.bps,
    required this.higherIsBetter,
  });

  final int bps;

  /// Net worth going up is good news; spending going up is not. The same
  /// number therefore takes a different tone depending on what it measures.
  final bool higherIsBetter;

  @override
  Widget build(BuildContext context) {
    final rising = bps > 0;
    final flat = bps == 0;
    final good = flat || rising == higherIsBetter;
    final percent = (bps.abs() / 100);
    // One decimal below 10% where precision is meaningful, none above it,
    // where it is noise.
    final text = percent >= 10
        ? percent.toStringAsFixed(0)
        : percent.toStringAsFixed(1).replaceAll('.', ',');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: good ? AppColors.paleMoss : AppColors.paleClay,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            flat
                ? Icons.remove
                : (rising ? Icons.arrow_upward : Icons.arrow_downward),
            size: 13,
            color: good ? AppColors.forest : AppColors.deepClay,
          ),
          const SizedBox(width: 3),
          Text(
            flat ? 'tetap' : '$text%',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: good ? AppColors.forest : AppColors.deepClay,
            ),
          ),
        ],
      ),
    );
  }
}

/// Spending per week, as bars.
///
/// Bars because spending is a flow: each week is a separate quantity that
/// starts from zero, and a line would imply the weeks flow into one another.
/// Touching a bar names it, so the chart can be read precisely without
/// labelling all eight columns and turning it into a table.
class SpendingChart extends StatefulWidget {
  const SpendingChart({super.key, required this.trends});

  final Trends trends;

  @override
  State<SpendingChart> createState() => _SpendingChartState();
}

class _SpendingChartState extends State<SpendingChart> {
  /// The bar being touched, or null when nothing is. On a phone there is no
  /// hover, so the equivalent gesture is press and drag along the chart.
  int? _active;

  @override
  Widget build(BuildContext context) {
    final buckets = widget.trends.buckets;
    final peak = buckets.fold<int>(
      0,
      (m, b) => b.spent.atomic > m ? b.spent.atomic : m,
    );
    final finished = widget.trends.finished;
    final latest = finished.isNotEmpty ? finished.last : null;
    final selected = _active == null ? null : buckets[_active!];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                'Pengeluaran per minggu',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (widget.trends.canCompare &&
                widget.trends.spendChangeBps != null)
              ChangePill(
                bps: widget.trends.spendChangeBps!,
                higherIsBetter: false,
              ),
          ],
        ),
        const SizedBox(height: 3),
        // The caption is the readout: it names the touched week while a finger
        // is down, and falls back to the last finished one.
        SizedBox(
          height: 20,
          child: Text(
            selected != null
                ? '${selected.label}: ${selected.spent.format()}'
                      '${selected.complete ? '' : ' (berjalan)'}'
                : latest == null
                ? 'Minggu berjalan belum selesai.'
                : 'Minggu ${latest.label} ${latest.spent.format()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected != null ? AppColors.ink : AppColors.mutedInk,
              fontSize: 13,
              fontWeight: selected != null ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ChartScrubber(
          count: buckets.length,
          onActive: (value) => setState(() => _active = value),
          child: SizedBox(
            height: 128,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < buckets.length; i++)
                  Expanded(
                    child: _SpendBar(
                      bucket: buckets[i],
                      peak: peak,
                      // Once one bar is chosen the others step back, so the
                      // selection is visible without moving anything.
                      dimmed: _active != null && _active != i,
                      selected: _active == i,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Turns a press and a drag across a row of [count] equal slots into the index
/// under the finger. Shared by both charts so they answer to the same gesture.
class _ChartScrubber extends StatelessWidget {
  const _ChartScrubber({
    required this.count,
    required this.onActive,
    required this.child,
  });

  final int count;
  final ValueChanged<int?> onActive;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        void update(Offset local) {
          final slot = constraints.maxWidth / count;
          final index = (local.dx / slot).floor().clamp(0, count - 1);
          onActive(index);
        }

        // Listener rather than GestureDetector for the press itself: a tap
        // gesture only resolves once the arena settles, so a finger held
        // still on a bar would show nothing until it moved. The readout has
        // to appear the moment the screen is touched.
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => update(event.localPosition),
          onPointerMove: (event) => update(event.localPosition),
          onPointerUp: (_) => onActive(null),
          onPointerCancel: (_) => onActive(null),
          child: child,
        );
      },
    );
  }
}

class _SpendBar extends StatelessWidget {
  const _SpendBar({
    required this.bucket,
    required this.peak,
    required this.dimmed,
    required this.selected,
  });

  final TrendBucket bucket;
  final int peak;
  final bool dimmed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ratio = peak == 0 ? 0.0 : bucket.spent.atomic / peak;

    return Semantics(
      label:
          '${bucket.label}: ${bucket.spent.format()}'
          '${bucket.complete ? '' : ', minggu berjalan'}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // A week with spending always gets a visible sliver, so a
                  // small week reads as small rather than as nothing recorded.
                  // The outlined bar needs more of a floor than the solid one:
                  // below about 14px its two borders meet and it reads as a
                  // line rather than a bar.
                  final floor = bucket.complete ? 4.0 : 14.0;
                  final height = bucket.spent.atomic == 0
                      ? 2.0
                      : (constraints.maxHeight * ratio).clamp(
                          floor,
                          constraints.maxHeight,
                        );
                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 120),
                      opacity: dimmed ? 0.35 : 1,
                      child: Container(
                        height: height,
                        decoration: BoxDecoration(
                          // The running week is drawn lighter and outlined:
                          // its bar is short because the week is young, not
                          // because spending fell.
                          color: bucket.complete
                              ? AppColors.forest
                              : AppColors.paleMoss,
                          border: bucket.complete
                              ? null
                              : Border.all(color: AppColors.moss, width: 2),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                bucket.label,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.1,
                  color: selected
                      ? AppColors.ink
                      : (bucket.complete
                            ? AppColors.quietInk
                            : AppColors.mutedInk),
                  fontWeight: selected || !bucket.complete
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Closing net worth per week, as a line.
///
/// A line because net worth is a level that carries from one week into the
/// next, which is exactly what bars starting from zero would hide.
class NetWorthChart extends StatefulWidget {
  const NetWorthChart({super.key, required this.trends});

  final Trends trends;

  @override
  State<NetWorthChart> createState() => _NetWorthChartState();
}

class _NetWorthChartState extends State<NetWorthChart> {
  int? _active;

  @override
  Widget build(BuildContext context) {
    final buckets = widget.trends.buckets;
    final values = [for (final b in buckets) b.netWorth.atomic];
    final low = values.reduce((a, b) => a < b ? a : b);
    final high = values.reduce((a, b) => a > b ? a : b);
    final selected = _active == null ? null : buckets[_active!];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                'Total aset per minggu',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (widget.trends.canCompare && widget.trends.changeBps != null)
              ChangePill(bps: widget.trends.changeBps!, higherIsBetter: true),
          ],
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 20,
          child: Text(
            selected != null
                ? '${selected.label}: ${selected.netWorth.format()}'
                : 'Sekarang ${buckets.last.netWorth.format()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected != null ? AppColors.ink : AppColors.mutedInk,
              fontSize: 13,
              fontWeight: selected != null ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          label:
              'Grafik total aset, '
              '${buckets.first.label} ${buckets.first.netWorth.compact} '
              'sampai ${buckets.last.label} ${buckets.last.netWorth.compact}',
          child: _ChartScrubber(
            count: buckets.length,
            onActive: (value) => setState(() => _active = value),
            child: SizedBox(
              height: 118,
              child: CustomPaint(
                painter: NetWorthPainter(
                  buckets: buckets,
                  low: low,
                  high: high,
                  active: _active,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              buckets.first.label,
              style: const TextStyle(fontSize: 10.5, color: AppColors.quietInk),
            ),
            const Spacer(),
            Text(
              buckets.last.label,
              style: const TextStyle(fontSize: 10.5, color: AppColors.quietInk),
            ),
          ],
        ),
      ],
    );
  }
}

class NetWorthPainter extends CustomPainter {
  const NetWorthPainter({
    required this.buckets,
    required this.low,
    required this.high,
    this.active,
  });

  final List<TrendBucket> buckets;
  final int low;
  final int high;
  final int? active;

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.length < 2) return;

    // Headroom above and below so the line never touches the edges of its box,
    // which would read as clipped.
    const padding = 14.0;
    // The stroke is centred on the path, so the first and last points need
    // half its width in from the sides or the end caps are shaved off.
    const inset = 3.0;
    final usable = size.height - padding * 2;
    final span = (high - low).abs();

    double x(int i) =>
        inset + (size.width - inset * 2) * i / (buckets.length - 1);
    double y(int value) {
      // A flat run has no range to scale against, so it sits on the middle
      // line rather than dividing by zero.
      if (span == 0) return size.height / 2;
      return padding + usable * (1 - (value - low) / span);
    }

    final points = [
      for (var i = 0; i < buckets.length; i++)
        Offset(x(i), y(buckets[i].netWorth.atomic)),
    ];

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      line.lineTo(points[i].dx, points[i].dy);
    }

    // A soft fill under the line gives the shape weight without a second
    // colour competing with the bars above.
    final fill = Path.from(line)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x26234B38), Color(0x00234B38)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.forest
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    // Only the latest point is marked by default, because that is the one the
    // caption states; dotting every week would add marks that say nothing.
    void dot(Offset at, {required bool emphasised}) {
      canvas.drawCircle(
        at,
        emphasised ? 5.5 : 4.5,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        at,
        emphasised ? 5.5 : 4.5,
        Paint()
          ..color = AppColors.forest
          ..strokeWidth = emphasised ? 3 : 2.4
          ..style = PaintingStyle.stroke,
      );
    }

    final index = active;
    if (index != null) {
      // A rule down to the axis ties the touched point to its week label.
      canvas.drawLine(
        Offset(points[index].dx, points[index].dy + 6),
        Offset(points[index].dx, size.height),
        Paint()
          ..color = AppColors.moss.withValues(alpha: 0.45)
          ..strokeWidth = 1.2,
      );
      dot(points[index], emphasised: true);
    } else {
      dot(points.last, emphasised: false);
    }
  }

  @override
  bool shouldRepaint(NetWorthPainter old) =>
      old.buckets != buckets ||
      old.low != low ||
      old.high != high ||
      old.active != active;
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

  /// Email rarely says which of the household's accounts paid, so the
  /// person confirming picks it (and the category) before anything posts.
  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _error = null);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) =>
          ConfirmCandidateSheet(auth: widget.auth, candidate: widget.candidate),
    );
    if (saved == true && mounted) {
      setState(() => _busy = true);
      await widget.onDone();
    }
  }

  Future<void> _openDetail() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            CandidateDetailScreen(auth: widget.auth, id: widget.candidate.id),
      ),
    );
    if (mounted) await widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.candidate;
    final auth = widget.auth;
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.container),
        side: BorderSide(
          color: c.needsInput ? AppColors.clay : AppColors.hairline,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.container),
        onTap: _busy ? null : _openDetail,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.recipientName ?? c.description ?? 'Tanpa keterangan',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15.5,
                ),
              ),
              if (c.recipientAccount != null) ...[
                const SizedBox(height: 2),
                Text(
                  c.recipientAccount!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
              const SizedBox(height: 9),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      c.amount?.format() ?? 'Jumlah belum terbaca',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                        color: c.amount == null
                            ? AppColors.clay
                            : AppColors.ink,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.mutedInk),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                candidateStatusLine(c),
                style: TextStyle(
                  fontSize: 12.5,
                  color: c.needsInput || !c.isRecordable
                      ? AppColors.clay
                      : AppColors.quietInk,
                  fontWeight: c.needsInput || !c.isRecordable
                      ? FontWeight.w600
                      : FontWeight.w400,
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
                      onPressed: _busy || c.needsInput || !c.isRecordable
                          ? null
                          : _confirm,
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
                          : () => _act(
                              () => auth.rejectCandidate(c.id, c.version),
                            ),
                      child: const Text('Tolak'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line under the amount that says why the card can or cannot be posted.
String candidateStatusLine(Candidate c) {
  if (c.needsInput) return 'Perlu dilengkapi sebelum bisa dikonfirmasi';
  final from = c.issuer;
  if (c.transactionType == 'income') {
    return from == null ? 'Pemasukan dari email' : 'Pemasukan dari email $from';
  }
  if (c.transactionType == 'transfer') {
    return from == null
        ? 'Pindah dana dari email'
        : 'Pindah dana dari email $from';
  }
  return from == null ? 'Dari email transaksi' : 'Dari email $from';
}

/// The account most likely to have paid: the one the email was matched to,
/// else the only account whose name mentions the sending bank. Several
/// matches (Jago for two people) means guessing, so none is preselected.
String? suggestedAccountId(Candidate c, List<LedgerAccount> accounts) {
  if (c.accountId != null && accounts.any((a) => a.id == c.accountId)) {
    return c.accountId;
  }
  final issuer = c.issuer?.trim().toLowerCase();
  if (issuer == null || issuer.isEmpty) return null;
  final matches = accounts
      .where((a) => a.name.toLowerCase().contains(issuer))
      .toList();
  return matches.length == 1 ? matches.single.id : null;
}

/// Helper text under a field Jev filled in, so the person knows it is a
/// guess to check rather than something read from the email.
String? jevSuggestionNote(Candidate c, String field, String? currentValue) {
  if (!c.isSuggested(field)) return null;
  final suggested = switch (field) {
    'account_id' => c.accountId,
    'destination_account_id' => c.destinationAccountId,
    'category_id' => c.categoryId,
    _ => null,
  };
  return currentValue != null && currentValue == suggested
      ? 'Saran Jev, ubah bila keliru'
      : null;
}

class ConfirmCandidateSheet extends StatefulWidget {
  const ConfirmCandidateSheet({
    super.key,
    required this.auth,
    required this.candidate,
  });

  final AuthRepository auth;
  final Candidate candidate;

  @override
  State<ConfirmCandidateSheet> createState() => _ConfirmCandidateSheetState();
}

class _ConfirmCandidateSheetState extends State<ConfirmCandidateSheet> {
  late Future<(List<LedgerAccount>, List<SpendingCategory>)> _choices;
  String? _accountId;
  String? _categoryId;
  String? _destinationAccountId;
  bool _initialised = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _choices = _load();
  }

  Future<(List<LedgerAccount>, List<SpendingCategory>)> _load() async {
    final currency = widget.candidate.amount?.currency;
    final results = await Future.wait([
      widget.auth.accounts(),
      widget.auth.categories(),
    ]);
    // A card payment or bank fee leaves a bank, wallet, cash, or pocket.
    // Investments and gold are valued, not spent from.
    final accounts = (results[0] as List<LedgerAccount>)
        .where((a) => currency == null || a.currency == currency)
        .where(
          (a) =>
              !const {'investment', 'physical_asset', 'other'}.contains(a.kind),
        )
        .toList();
    final categories = (results[1] as List<SpendingCategory>)
        .where((c) => c.type == (widget.candidate.transactionType ?? 'expense'))
        .toList();
    return (accounts, categories);
  }

  void _initialise(List<LedgerAccount> accounts, List<SpendingCategory> cats) {
    if (_initialised) return;
    _initialised = true;
    _accountId = suggestedAccountId(widget.candidate, accounts);
    // A pick only stands if it is still one of the offered accounts and not
    // the source itself; otherwise the dropdown would hold a value it cannot
    // show.
    final destination = widget.candidate.destinationAccountId;
    _destinationAccountId =
        destination != null &&
            destination != _accountId &&
            accounts.any((a) => a.id == destination)
        ? destination
        : null;
    final category = widget.candidate.categoryId;
    // Only the household's catch-all is a safe default. Falling back to the
    // first name alphabetically would file a card payment as "appliance".
    _categoryId =
        (category != null && cats.any((c) => c.id == category)
            ? category
            : null) ??
        cats
            .where(
              (c) =>
                  c.name ==
                  (widget.candidate.transactionType == 'income'
                      ? 'General income'
                      : 'General expense'),
            )
            .firstOrNull
            ?.id;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_accountId == null) {
      setState(() => _error = 'Pilih dulu akun yang membayar.');
      return;
    }
    if (widget.candidate.transactionType == 'transfer' &&
        _destinationAccountId == null) {
      setState(() => _error = 'Pilih akun tujuan.');
      return;
    }
    if (widget.candidate.transactionType != 'transfer' && _categoryId == null) {
      setState(() => _error = 'Pilih kategori dulu.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.auth.confirmCandidate(
        widget.candidate.id,
        widget.candidate.version,
        accountId: _accountId!,
        categoryId: _categoryId,
        destinationAccountId: _destinationAccountId,
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
    final c = widget.candidate;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 22, 22, 24 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Masukkan ke catatan',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 14),
            Text(
              c.recipientName ?? c.description ?? 'Tanpa keterangan',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              c.amount?.format() ?? '',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            FutureBuilder<(List<LedgerAccount>, List<SpendingCategory>)>(
              future: _choices,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Memuat akun dan kategori…'),
                      SizedBox(height: 8),
                      LinearProgressIndicator(color: AppColors.forest),
                    ],
                  );
                }
                if (snapshot.hasError) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AuthErrorNote(
                        message: describeAuthError(snapshot.error!),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _choices = _load()),
                        child: const Text('Coba lagi'),
                      ),
                    ],
                  );
                }
                final (accounts, categories) = snapshot.data!;
                if (accounts.isEmpty) {
                  return const AuthErrorNote(
                    message:
                        'Belum ada akun dengan mata uang ini. Tambahkan akun '
                        'lewat Lihat akun dan riwayat di Beranda.',
                  );
                }
                if (categories.isEmpty && c.transactionType != 'transfer') {
                  return const AuthErrorNote(
                    message:
                        'Belum ada kategori pengeluaran. Tambahkan lewat '
                        'Atur kategori & anggaran di Beranda.',
                  );
                }
                _initialise(accounts, categories);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _accountId,
                      hint: const Text('Pilih akun'),
                      decoration: InputDecoration(
                        labelText: c.transactionType == 'income'
                            ? 'Masuk ke akun'
                            : 'Dari akun',
                        helperText: jevSuggestionNote(
                          c,
                          'account_id',
                          _accountId,
                        ),
                      ),
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
                      onChanged: _saving
                          ? null
                          : (value) => setState(() {
                              _accountId = value;
                              _error = null;
                            }),
                    ),
                    const SizedBox(height: 14),
                    if (c.transactionType == 'transfer')
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _destinationAccountId,
                        hint: const Text('Pilih akun tujuan'),
                        decoration: InputDecoration(
                          labelText: 'Ke akun',
                          helperText: jevSuggestionNote(
                            c,
                            'destination_account_id',
                            _destinationAccountId,
                          ),
                        ),
                        items: [
                          for (final a in accounts.where(
                            (a) => a.id != _accountId,
                          ))
                            DropdownMenuItem(
                              value: a.id,
                              child: Text(
                                a.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) => setState(() {
                                _destinationAccountId = value;
                                _error = null;
                              }),
                      )
                    else
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _categoryId,
                        hint: const Text('Pilih kategori'),
                        decoration: InputDecoration(
                          labelText: 'Kategori',
                          helperText: jevSuggestionNote(
                            c,
                            'category_id',
                            _categoryId,
                          ),
                        ),
                        items: [
                          for (final cat in categories)
                            DropdownMenuItem(
                              value: cat.id,
                              child: Text(
                                cat.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) => setState(() {
                                _categoryId = value;
                                _error = null;
                              }),
                      ),
                  ],
                );
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              AuthErrorNote(message: _error!),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
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
    );
  }
}

class CandidateDetailScreen extends StatefulWidget {
  const CandidateDetailScreen({
    super.key,
    required this.auth,
    required this.id,
  });

  final AuthRepository auth;
  final String id;

  @override
  State<CandidateDetailScreen> createState() => _CandidateDetailScreenState();
}

class _CandidateDetailScreenState extends State<CandidateDetailScreen> {
  late Future<CandidateDetail> _detail;

  Future<void> _edit(Candidate candidate) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            CandidateEditScreen(auth: widget.auth, candidate: candidate),
      ),
    );
    if (changed == true && mounted) {
      setState(() {
        _detail = widget.auth.candidateDetail(widget.id);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _detail = widget.auth.candidateDetail(widget.id);
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  Widget _field(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.mutedInk, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.surface,
    appBar: AppBar(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      title: const Text('Detail usulan'),
    ),
    body: FutureBuilder<CandidateDetail>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const DataStateView(
            icon: Icons.mark_email_read_outlined,
            title: 'Membuka detail',
            message: 'Sedang mengambil usulan transaksi.',
            loading: true,
          );
        }
        if (snapshot.hasError) {
          return DataStateView(
            icon: Icons.sync_problem_outlined,
            title: 'Detail belum dapat dibuka',
            message: describeAuthError(snapshot.error!),
            actionLabel: 'Coba lagi',
            onAction: () => setState(() {
              _detail = widget.auth.candidateDetail(widget.id);
            }),
          );
        }
        final detail = snapshot.data!;
        final c = detail.candidate;
        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
          children: [
            Text(
              c.recipientName ?? c.description ?? 'Tanpa keterangan',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (c.recipientAccount != null) ...[
              const SizedBox(height: 5),
              Text(
                c.recipientAccount!,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              c.amount?.format() ?? 'Jumlah belum terbaca',
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 28),
            OutlinedButton.icon(
              onPressed: () => _edit(c),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Ubah usulan'),
            ),
            const SizedBox(height: 18),
            const Divider(color: AppColors.hairline),
            const SizedBox(height: 22),
            _field(
              'Tanggal transaksi',
              c.occurredAt == null ? 'Belum terbaca' : _date(c.occurredAt!),
            ),
            _field(
              'Dari email',
              detail.issuer ??
                  detail.senderDomain ??
                  'Pengirim tidak diketahui',
            ),
            _field('Diterima', _date(detail.receivedAt)),
            if (detail.subject != null && detail.subject != c.description)
              _field('Subjek email', detail.subject!),
            if (!c.isRecordable)
              Text(
                candidateStatusLine(c),
                style: const TextStyle(
                  color: AppColors.clay,
                  fontWeight: FontWeight.w600,
                ),
              )
            else if (c.needsInput)
              const Text(
                'Usulan ini perlu dilengkapi sebelum masuk ke catatan.',
                style: TextStyle(
                  color: AppColors.clay,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        );
      },
    ),
  );
}

class CandidateEditScreen extends StatefulWidget {
  const CandidateEditScreen({
    super.key,
    required this.auth,
    required this.candidate,
  });

  final AuthRepository auth;
  final Candidate candidate;

  @override
  State<CandidateEditScreen> createState() => _CandidateEditScreenState();
}

class _CandidateEditScreenState extends State<CandidateEditScreen> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.candidate.amount?.atomic.toString() ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.candidate.description ?? '',
  );
  late DateTime _occurredAt = widget.candidate.occurredAt ?? DateTime.now();
  late String _type = widget.candidate.transactionType ?? 'expense';
  late String? _accountId = widget.candidate.accountId;
  late String? _categoryId = widget.candidate.categoryId;
  late String? _destinationId = widget.candidate.destinationAccountId;
  late final Future<(List<LedgerAccount>, List<SpendingCategory>)> _choices =
      _load();
  bool _saving = false;
  String? _error;

  Future<(List<LedgerAccount>, List<SpendingCategory>)> _load() async {
    final result = await Future.wait([
      widget.auth.accounts(),
      widget.auth.categories(),
    ]);
    return (
      result[0] as List<LedgerAccount>,
      result[1] as List<SpendingCategory>,
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (time == null || !mounted) return;
    setState(
      () => _occurredAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _save() async {
    final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (amount == null || amount <= 0 || _description.text.trim().isEmpty) {
      setState(() => _error = 'Isi jumlah dan keterangan.');
      return;
    }
    if (_type == 'transfer' &&
        _destinationId != null &&
        _destinationId == _accountId) {
      setState(() => _error = 'Pilih akun tujuan yang berbeda.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.auth.editCandidate(widget.candidate.id, {
        'version': widget.candidate.version,
        'amount_atomic': amount,
        'currency': widget.candidate.amount?.currency ?? 'IDR',
        'description': _description.text.trim(),
        'occurred_at': _occurredAt.toUtc().toIso8601String(),
        'account_id': _accountId,
        'transaction_type': _type,
        'category_id': _type == 'transfer' ? null : _categoryId,
        'destination_account_id': _type == 'transfer' ? _destinationId : null,
      });
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = describeAuthError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.surface,
    appBar: AppBar(title: const Text('Ubah usulan')),
    body: FutureBuilder<(List<LedgerAccount>, List<SpendingCategory>)>(
      future: _choices,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError) {
            return Center(child: Text(describeAuthError(snapshot.error!)));
          }
          return const Center(child: CircularProgressIndicator());
        }
        final (allAccounts, allCategories) = snapshot.data!;
        final currency = widget.candidate.amount?.currency ?? 'IDR';
        final accounts = allAccounts
            .where(
              (a) =>
                  a.currency == currency &&
                  !const {
                    'investment',
                    'physical_asset',
                    'other',
                  }.contains(a.kind),
            )
            .toList();
        final categories = allCategories.where((c) => c.type == _type).toList();
        if (_accountId != null && !accounts.any((a) => a.id == _accountId)) {
          _accountId = null;
        }
        if (_categoryId != null &&
            !categories.any((c) => c.id == _categoryId)) {
          _categoryId = null;
        }
        if (_destinationId != null &&
            !accounts.any((a) => a.id == _destinationId)) {
          _destinationId = null;
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
          children: [
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Jumlah ($currency, satuan terkecil)',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _description,
              maxLength: 240,
              decoration: const InputDecoration(labelText: 'Keterangan'),
            ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _chooseDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(
                '${_occurredAt.day}/${_occurredAt.month}/${_occurredAt.year} '
                '${_occurredAt.hour.toString().padLeft(2, '0')}:${_occurredAt.minute.toString().padLeft(2, '0')}',
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Jenis transaksi'),
              items: const [
                DropdownMenuItem(value: 'expense', child: Text('Pengeluaran')),
                DropdownMenuItem(value: 'income', child: Text('Pemasukan')),
                DropdownMenuItem(value: 'transfer', child: Text('Pindah dana')),
              ],
              onChanged: (value) => setState(() {
                _type = value ?? 'expense';
                _categoryId = null;
              }),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _accountId,
              decoration: InputDecoration(
                labelText: _type == 'income' ? 'Masuk ke akun' : 'Dari akun',
                helperText: jevSuggestionNote(
                  widget.candidate,
                  'account_id',
                  _accountId,
                ),
              ),
              items: [
                for (final a in accounts)
                  DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (value) => setState(() {
                _accountId = value;
                if (_destinationId == value) _destinationId = null;
              }),
            ),
            const SizedBox(height: 14),
            if (_type == 'transfer')
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _destinationId,
                decoration: InputDecoration(
                  labelText: 'Ke akun',
                  helperText: jevSuggestionNote(
                    widget.candidate,
                    'destination_account_id',
                    _destinationId,
                  ),
                ),
                items: [
                  for (final a in accounts.where((a) => a.id != _accountId))
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (value) => setState(() => _destinationId = value),
              )
            else
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _categoryId,
                decoration: InputDecoration(
                  labelText: 'Kategori',
                  helperText: jevSuggestionNote(
                    widget.candidate,
                    'category_id',
                    _categoryId,
                  ),
                ),
                items: [
                  for (final c in categories)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (value) => setState(() => _categoryId = value),
              ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              AuthErrorNote(message: _error!),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Menyimpan…' : 'Simpan perubahan'),
            ),
          ],
        );
      },
    ),
  );
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

int? parseMoneyInput(String raw, int minorUnit) {
  if (minorUnit == 0) return parseAmountInput(raw);
  final normalized = raw.trim().replaceAll('.', '').replaceAll(' ', '');
  final parts = normalized.split(',');
  if (parts.length > 2 ||
      parts.isEmpty ||
      !RegExp(r'^\d+$').hasMatch(parts.first)) {
    return null;
  }
  if (parts.length == 2 &&
      (parts.last.isEmpty ||
          parts.last.length > minorUnit ||
          !RegExp(r'^\d+$').hasMatch(parts.last))) {
    return null;
  }
  final scale = List<int>.generate(
    minorUnit,
    (index) => index,
  ).fold<int>(1, (value, _) => value * 10);
  final whole = int.tryParse(parts.first);
  final fraction = parts.length == 1
      ? 0
      : int.tryParse(parts.last.padRight(minorUnit, '0'));
  if (whole == null || fraction == null) return null;
  return whole * scale + fraction;
}

class LedgerDatePicker extends StatelessWidget {
  const LedgerDatePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: () async {
      final selected = await showDatePicker(
        context: context,
        initialDate: value ?? DateTime.now(),
        firstDate: DateTime(1900),
        lastDate: DateTime.now(),
      );
      if (selected != null) onChanged(selected);
    },
    icon: const Icon(Icons.calendar_today_outlined),
    label: Text(
      value == null
          ? 'Tanggal: hari ini'
          : 'Tanggal: ${value!.day}/${value!.month}/${value!.year}',
    ),
  );
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
  late Future<List<SpendingCategory>> _categories;
  late Future<Dashboard> _balances;
  String? _categoryId;
  String? _accountId;
  LedgerAccount? _selectedAccount;
  String _type = 'expense';
  String _entryKind = 'regular';
  DateTime? _occurredAt;
  bool _saving = false;
  String? _error;

  /// Generated once per sheet, not per attempt: a retry after a timeout must
  /// carry the same key or the money posts twice.
  final String _idempotencyKey = 'tx-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _accounts = widget.auth.accounts();
    _categories = widget.auth.categories();
    _balances = widget.auth.dashboard();
    unawaited(_balances.then<void>((_) {}, onError: (Object _) {}));
    _amount.addListener(_amountChanged);
  }

  void _amountChanged() {
    if (mounted && _entryKind == 'adjustment') setState(() {});
  }

  @override
  void dispose() {
    _amount.removeListener(_amountChanged);
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_accountId == null || _selectedAccount == null) {
      setState(() => _error = 'Pilih dulu akunnya.');
      return;
    }
    if ((_entryKind == 'regular' || _entryKind == 'refund') &&
        _categoryId == null) {
      setState(() => _error = 'Pilih kategori dulu.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_entryKind == 'adjustment') {
        await widget.auth.correctBalance(
          accountId: _accountId!,
          balanceAtomic: parseMoneyInput(
            _amount.text,
            _selectedAccount!.minorUnit,
          )!,
          idempotencyKey: _idempotencyKey,
        );
      } else {
        await widget.auth.createTransaction(
          accountId: _accountId!,
          categoryId: _entryKind == 'regular' || _entryKind == 'refund'
              ? _categoryId
              : null,
          transactionType: _entryKind == 'regular' ? _type : _entryKind,
          amountAtomic: parseMoneyInput(
            _amount.text,
            _selectedAccount!.minorUnit,
          )!,
          description: _description.text.trim(),
          occurredAt: _occurredAt,
          idempotencyKey: _idempotencyKey,
        );
      }
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
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _entryKind,
                decoration: const InputDecoration(labelText: 'Jenis catatan'),
                items: const [
                  DropdownMenuItem(
                    value: 'regular',
                    child: Text('Masuk / keluar'),
                  ),
                  DropdownMenuItem(
                    value: 'opening_balance',
                    child: Text('Saldo awal'),
                  ),
                  DropdownMenuItem(
                    value: 'refund',
                    child: Text('Pengembalian dana'),
                  ),
                  DropdownMenuItem(
                    value: 'adjustment',
                    child: Text('Koreksi saldo'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _entryKind = value ?? 'regular'),
              ),
              if (_entryKind == 'regular') ...[
                const SizedBox(height: 14),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'expense', label: Text('Keluar')),
                    ButtonSegment(value: 'income', label: Text('Masuk')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (value) =>
                      setState(() => _type = value.first),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: _selectedAccount?.minorUnit == 0
                    ? const [ThousandsFormatter()]
                    : null,
                decoration: InputDecoration(
                  labelText: _entryKind == 'adjustment'
                      ? 'Saldo saat ini'
                      : 'Jumlah',
                  prefixText:
                      '${_selectedAccount?.currency == 'IDR' ? 'Rp' : _selectedAccount?.currency ?? ''} ',
                  helperText: (_selectedAccount?.minorUnit ?? 0) > 0
                      ? 'Gunakan koma untuk desimal.'
                      : null,
                ),
                validator: (value) {
                  final parsed = parseMoneyInput(
                    value ?? '',
                    _selectedAccount?.minorUnit ?? 0,
                  );
                  if (parsed == null ||
                      (_entryKind != 'adjustment' && parsed <= 0)) {
                    return 'Isi jumlahnya.';
                  }
                  return null;
                },
              ),
              if (_entryKind == 'adjustment' && _selectedAccount != null) ...[
                const SizedBox(height: 10),
                FutureBuilder<Dashboard>(
                  future: _balances,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Text('Memuat saldo akun…');
                    }
                    if (snapshot.hasError) {
                      return TextButton(
                        onPressed: () => setState(() {
                          _balances = widget.auth.dashboard();
                          unawaited(
                            _balances.then<void>(
                              (_) {},
                              onError: (Object _) {},
                            ),
                          );
                        }),
                        child: const Text('Saldo gagal dimuat. Coba lagi'),
                      );
                    }
                    final current = snapshot.data!.holdings
                        .where((a) => a.accountId == _accountId)
                        .firstOrNull;
                    if (current == null) {
                      return const Text('Saldo akun tidak tersedia.');
                    }
                    final target = parseMoneyInput(
                      _amount.text,
                      _selectedAccount!.minorUnit,
                    );
                    final delta = target == null
                        ? null
                        : target - current.balance.atomic;
                    return Text(
                      'Saldo tercatat: ${current.balance.format()}${delta == null
                          ? ''
                          : delta == 0
                          ? ' · Tidak ada perubahan'
                          : ' · ${delta > 0 ? 'Bertambah' : 'Berkurang'} ${Money(atomic: delta.abs(), currency: current.balance.currency, minorUnit: current.balance.minorUnit).format()}'}',
                      style: const TextStyle(color: AppColors.mutedInk),
                    );
                  },
                ),
              ],
              if (_entryKind == 'regular' || _entryKind == 'refund') ...[
                const SizedBox(height: 14),
                FutureBuilder<List<SpendingCategory>>(
                  future: _categories,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Text('Memuat kategori…');
                    }
                    if (snapshot.hasError) {
                      return TextButton(
                        onPressed: () => setState(
                          () => _categories = widget.auth.categories(),
                        ),
                        child: const Text('Kategori gagal dimuat. Coba lagi'),
                      );
                    }
                    final type = _entryKind == 'refund' || _type == 'expense'
                        ? 'expense'
                        : 'income';
                    final choices = snapshot.data!
                        .where((c) => c.type == type)
                        .toList();
                    if (choices.isEmpty) {
                      return const Text(
                        'Belum ada kategori untuk jenis ini. Tambahkan di halaman Anggaran.',
                      );
                    }
                    final selected = choices.any((c) => c.id == _categoryId)
                        ? _categoryId
                        : choices.first.id;
                    _categoryId = selected;
                    return DropdownButtonFormField<String>(
                      key: ValueKey(type),
                      isExpanded: true,
                      initialValue: selected,
                      decoration: const InputDecoration(labelText: 'Kategori'),
                      items: [
                        for (final c in choices)
                          DropdownMenuItem(value: c.id, child: Text(c.name)),
                      ],
                      onChanged: (value) => setState(() => _categoryId = value),
                    );
                  },
                ),
              ],
              if (_entryKind != 'adjustment') ...[
                const SizedBox(height: 14),
                TextFormField(
                  controller: _description,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Keterangan'),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Tulis keperluannya.'
                      : null,
                ),
              ],
              if (_entryKind != 'adjustment') ...[
                const SizedBox(height: 14),
                LedgerDatePicker(
                  value: _occurredAt,
                  onChanged: (date) => setState(() => _occurredAt = date),
                ),
              ],
              const SizedBox(height: 14),
              FutureBuilder<List<LedgerAccount>>(
                future: _accounts,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Memuat akun…'),
                        SizedBox(height: 8),
                        LinearProgressIndicator(color: AppColors.forest),
                      ],
                    );
                  }
                  if (snapshot.hasError) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AuthErrorNote(
                          message: describeAuthError(snapshot.error!),
                        ),
                        TextButton(
                          onPressed: () => setState(
                            () => _accounts = widget.auth.accounts(),
                          ),
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    );
                  }
                  final accounts = snapshot.data ?? const <LedgerAccount>[];
                  if (accounts.isEmpty) {
                    return const AuthErrorNote(
                      message:
                          'Belum ada akun untuk dicatat. Tutup formulir ini, '
                          'lalu pilih Lihat akun dan riwayat untuk menambah akun.',
                    );
                  }
                  final choices = _entryKind == 'adjustment'
                      ? accounts
                            .where(
                              (a) => !const {
                                'investment',
                                'physical_asset',
                                'other',
                              }.contains(a.kind),
                            )
                            .toList()
                      : accounts;
                  if (choices.isEmpty) {
                    return const Text('Tidak ada akun yang dapat dikoreksi.');
                  }
                  if (!choices.any((a) => a.id == _accountId)) {
                    _accountId = choices.first.id;
                  }
                  final initialAccount = _selectedAccount == null;
                  _selectedAccount = choices
                      .where((a) => a.id == _accountId)
                      .firstOrNull;
                  if (initialAccount) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() {});
                    });
                  }
                  return DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _accountId,
                    decoration: const InputDecoration(labelText: 'Dari akun'),
                    items: [
                      for (final account in choices)
                        DropdownMenuItem(
                          value: account.id,
                          child: Text(
                            '${account.name} · ${account.currency}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _accountId = value;
                      _selectedAccount = accounts
                          .where((a) => a.id == value)
                          .firstOrNull;
                      _amount.clear();
                    }),
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
  final _destinationAmount = TextEditingController();
  final _description = TextEditingController(text: 'Pindah dana');
  late Future<List<LedgerAccount>> _accounts;
  String? _from;
  String? _to;
  DateTime? _occurredAt;
  LedgerAccount? _sourceAccount;
  LedgerAccount? _targetAccount;
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
    _destinationAmount.dispose();
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
        amountAtomic: parseMoneyInput(
          _amount.text,
          _sourceAccount?.minorUnit ?? 0,
        )!,
        destinationAmountAtomic:
            _sourceAccount?.currency == _targetAccount?.currency
            ? null
            : parseMoneyInput(
                _destinationAmount.text,
                _targetAccount?.minorUnit ?? 0,
              ),
        description: _description.text.trim(),
        occurredAt: _occurredAt,
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
                    return const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Memuat akun…'),
                        SizedBox(height: 8),
                        LinearProgressIndicator(color: AppColors.forest),
                      ],
                    );
                  }
                  if (snapshot.hasError) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AuthErrorNote(
                          message: describeAuthError(snapshot.error!),
                        ),
                        TextButton(
                          onPressed: () => setState(
                            () => _accounts = widget.auth.accounts(),
                          ),
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    );
                  }
                  final accounts = snapshot.data ?? const <LedgerAccount>[];
                  // A transfer needs somewhere to go, so one account is not
                  // enough and saying so beats an unusable form.
                  if (accounts.length < 2) {
                    return const AuthErrorNote(
                      message:
                          'Pindah dana butuh dua akun. Tutup formulir ini, '
                          'lalu pilih Lihat akun dan riwayat untuk menambah akun.',
                    );
                  }
                  _from ??= accounts.first.id;
                  _to ??= accounts[1].id;
                  final initialAccounts = _sourceAccount == null;
                  _sourceAccount = accounts
                      .where((a) => a.id == _from)
                      .firstOrNull;
                  _targetAccount = accounts
                      .where((a) => a.id == _to)
                      .firstOrNull;
                  if (initialAccounts) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() {});
                    });
                  }
                  return Column(
                    children: [
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _from,
                        decoration: const InputDecoration(labelText: 'Dari'),
                        items: [
                          for (final a in accounts)
                            DropdownMenuItem(
                              value: a.id,
                              child: Text(
                                '${a.name} · ${a.currency}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          _from = value;
                          _amount.clear();
                        }),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _to,
                        decoration: const InputDecoration(labelText: 'Ke'),
                        items: [
                          for (final a in accounts)
                            DropdownMenuItem(
                              value: a.id,
                              child: Text(
                                '${a.name} · ${a.currency}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          _to = value;
                          _destinationAmount.clear();
                        }),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: _sourceAccount?.minorUnit == 0
                    ? const [ThousandsFormatter()]
                    : null,
                decoration: InputDecoration(
                  labelText: 'Jumlah keluar',
                  prefixText:
                      '${_sourceAccount?.currency == 'IDR' ? 'Rp' : _sourceAccount?.currency ?? ''} ',
                  helperText: (_sourceAccount?.minorUnit ?? 0) > 0
                      ? 'Gunakan koma untuk desimal.'
                      : null,
                ),
                validator: (value) {
                  final parsed = parseMoneyInput(
                    value ?? '',
                    _sourceAccount?.minorUnit ?? 0,
                  );
                  if (parsed == null || parsed <= 0) return 'Isi jumlahnya.';
                  return null;
                },
              ),
              if (_sourceAccount != null &&
                  _targetAccount != null &&
                  _sourceAccount!.currency != _targetAccount!.currency) ...[
                const SizedBox(height: 14),
                TextFormField(
                  controller: _destinationAmount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: _targetAccount!.minorUnit == 0
                      ? const [ThousandsFormatter()]
                      : null,
                  decoration: InputDecoration(
                    labelText: 'Jumlah diterima',
                    prefixText: '${_targetAccount!.currency} ',
                    helperText: 'Masukkan jumlah sesudah penukaran.',
                  ),
                  validator: (value) {
                    final parsed = parseMoneyInput(
                      value ?? '',
                      _targetAccount!.minorUnit,
                    );
                    return parsed == null || parsed <= 0
                        ? 'Isi jumlah yang diterima.'
                        : null;
                  },
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                AuthErrorNote(message: _error!),
              ],
              const SizedBox(height: 14),
              LedgerDatePicker(
                value: _occurredAt,
                onChanged: (date) => setState(() => _occurredAt = date),
              ),
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
              Navigator.pushNamed(context, '/gmail');
            },
            icon: const Icon(Icons.mark_email_read_outlined),
            label: const Text('Hubungkan Gmail'),
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
