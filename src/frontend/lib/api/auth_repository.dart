import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'api_client.dart';
import 'models.dart';
import 'token_store.dart';

/// Web client ID from Google Cloud Console. The backend verifies the ID token's
/// `aud` against this exact value, so the Android and iOS client IDs will not
/// work here.
const _googleServerClientId = String.fromEnvironment('RUMPUN_GOOGLE_CLIENT_ID');
const _googleIosServerClientId = String.fromEnvironment(
  'RUMPUN_GOOGLE_IOS_CLIENT_ID',
);

String get _platformGoogleServerClientId =>
    defaultTargetPlatform == TargetPlatform.iOS
    ? _googleIosServerClientId
    : _googleServerClientId;

/// Raised when the app was built without a Google client ID. Sign-in is the
/// only way in, so this is a build error the user needs to see, not a silently
/// hidden button.
class GoogleNotConfigured implements Exception {
  const GoogleNotConfigured();
}

/// Narrow view of the pieces of Google sign-in this app uses, so tests can
/// stand in for the plugin singleton.
abstract class GoogleAuthenticator {
  Future<void> initialize(String serverClientId);
  Future<String?> authenticateAndGetIdToken();
  Future<void> signOut();
}

class PluginGoogleAuthenticator implements GoogleAuthenticator {
  const PluginGoogleAuthenticator();

  @override
  Future<void> initialize(String serverClientId) =>
      GoogleSignIn.instance.initialize(serverClientId: serverClientId);

  @override
  Future<String?> authenticateAndGetIdToken() async {
    final account = await GoogleSignIn.instance.authenticate();
    return account.authentication.idToken;
  }

  @override
  Future<void> signOut() => GoogleSignIn.instance.signOut();
}

class AuthRepository extends ChangeNotifier {
  AuthRepository({
    ApiClient? client,
    TokenStore? store,
    GoogleAuthenticator? google,
    bool? googleConfigured,
  }) : _client = client ?? ApiClient(),
       _store = store ?? const SecureTokenStore(),
       _google = google ?? const PluginGoogleAuthenticator(),
       _googleConfigured =
           googleConfigured ?? _platformGoogleServerClientId.isNotEmpty;

  final ApiClient _client;
  final TokenStore _store;
  final GoogleAuthenticator _google;
  final bool _googleConfigured;

  AuthSession? _session;
  bool _googleReady = false;
  String? _registeredPushToken;
  Future<void>? _pushRegistration;

  /// The refresh in flight, if any. Refresh tokens rotate and the server
  /// revokes a whole family when one is replayed, so several screens hitting
  /// 401 at once must share a single refresh rather than each spending the
  /// same token.
  Future<bool>? _refreshing;

  AuthSession? get session => _session;
  String get apiBaseUrl => _client.baseUrl;
  bool get isSignedIn => _session != null;
  bool get isConfigured => _googleConfigured;

  /// Raised when the session is gone for good and the user has to sign in
  /// again. Screens listen for this rather than inspecting status codes.
  static bool isSessionExpired(Object error) =>
      error is ApiException && error.code == 'session_expired';

  /// True when the signed-in user has not joined a household yet.
  bool get needsOnboarding => _session?.needsOnboarding ?? false;

  /// True when the signed-in owner still has to name their household.
  bool get needsHouseholdSetup => _session?.needsHouseholdSetup ?? false;

  List<InviteSummary> get pendingInvites =>
      _session?.pendingInvites ?? const [];

  Future<void> _ensureGoogleInitialized() async {
    if (_googleReady) return;
    await _google.initialize(_platformGoogleServerClientId);
    _googleReady = true;
  }

  Future<void> _persist(AuthSession session) async {
    _session = session;
    await _store.write(session.refreshToken);
    notifyListeners();
  }

  /// Exchanges a stored refresh token for a live session on app start.
  /// Returns false when there is nothing stored or the token no longer works.
  Future<bool> restore() async {
    final stored = await _store.read();
    if (stored == null) return false;
    try {
      await _persist(await _client.refresh(stored));
      return true;
    } on ApiException {
      await _store.clear();
      return false;
    } on NetworkException {
      return false;
    }
  }

  /// Throws [GoogleSignInException] with code `canceled` when the user dismisses
  /// the account picker; callers treat that as a no-op rather than an error.
  Future<void> signInWithGoogle() async {
    if (!_googleConfigured) throw const GoogleNotConfigured();
    await _ensureGoogleInitialized();
    final idToken = await _google.authenticateAndGetIdToken();
    if (idToken == null) {
      throw const NetworkException(
        'Google tidak mengirim token identitas. Coba lagi.',
      );
    }
    await _persist(await _client.loginWithGoogle(idToken));
  }

  AuthSession _requireSession() {
    final current = _session;
    if (current == null) {
      throw const NetworkException('Sesi berakhir. Masuk lagi untuk lanjut.');
    }
    return current;
  }

  /// Trades the stored refresh token for a fresh access token.
  /// Returns false when the refresh token itself is no longer valid, which is
  /// the only case that genuinely requires signing in again.
  Future<bool> _refreshSession() {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;

    final attempt = () async {
      final stored = await _store.read();
      if (stored == null) return false;
      try {
        await _persist(await _client.refresh(stored));
        return true;
      } on ApiException {
        // The server rejected the refresh token: revoked, reused, or expired.
        // Nothing local can recover from that.
        await _store.clear();
        _session = null;
        notifyListeners();
        return false;
      }
      // A NetworkException is deliberately not caught. Being offline is not
      // the same as being signed out, and clearing the token here would log
      // the household out every time the train goes into a tunnel.
    }();

    _refreshing = attempt;
    return attempt.whenComplete(() => _refreshing = null);
  }

  /// Runs an authenticated call, renewing the access token once if the server
  /// says it has expired.
  ///
  /// The access token lives for 15 minutes while the refresh token lives for
  /// 30 days, so an app left open overnight will always meet a 401 first. That
  /// is a routine event, not an error worth showing anyone.
  Future<T> _authed<T>(Future<T> Function(String accessToken) call) async {
    try {
      return await call(_requireSession().accessToken);
    } on ApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      if (!await _refreshSession()) {
        throw const ApiException(
          statusCode: 401,
          code: 'session_expired',
          message: 'Sesi berakhir. Masuk lagi untuk lanjut.',
        );
      }
      // Only ever retried once: if the freshly minted token is also rejected,
      // the problem is not staleness and retrying would spin.
      return call(_requireSession().accessToken);
    }
  }

  /// Starts a household with this user as its owner.
  Future<void> createHousehold({
    required String name,
    required String baseCurrency,
  }) async {
    final household = await _authed(
      (token) => _client.createHousehold(
        accessToken: token,
        name: name,
        baseCurrency: baseCurrency,
      ),
    );
    _session = _requireSession().withHousehold(household);
    notifyListeners();
  }

  /// Joins the household that invited this email address.
  Future<void> acceptInvite(String inviteId) async {
    final household = await _authed(
      (token) => _client.acceptInvite(accessToken: token, inviteId: inviteId),
    );
    _session = _requireSession().withHousehold(household);
    notifyListeners();
  }

  /// Turns down an invitation, leaving the user free to start their own.
  Future<void> declineInvite(String inviteId) async {
    await _authed(
      (token) => _client.declineInvite(accessToken: token, inviteId: inviteId),
    );
    final current = _requireSession();
    _session = current.withInvites(
      current.pendingInvites.where((i) => i.id != inviteId).toList(),
    );
    notifyListeners();
  }

  /// Renames a household that still carries its generated name.
  Future<void> completeHouseholdSetup({
    required String name,
    required String baseCurrency,
  }) async {
    final household = await _authed(
      (token) => _client.updateHousehold(
        accessToken: token,
        name: name,
        baseCurrency: baseCurrency,
      ),
    );
    _session = _requireSession().withHousehold(household);
    notifyListeners();
  }

  Future<Dashboard> dashboard() => _authed(_client.dashboard);

  Future<Trends> trends({
    String granularity = 'week',
    int periods = 8,
    String? currency,
  }) => _authed(
    (token) => _client.trends(
      token,
      granularity: granularity,
      periods: periods,
      currency: currency,
    ),
  );

  Future<CandidateList> candidates() => _authed((token) async {
    final items = <Candidate>[];
    String? cursor;
    do {
      final page = await _client.candidates(token, cursor: cursor);
      items.addAll(page.items);
      cursor = page.nextCursor;
    } while (cursor != null);
    return CandidateList(items: items, nextCursor: null);
  });

  Future<CandidateDetail> candidateDetail(String id) =>
      _authed((token) => _client.candidateDetail(token, id));

  Future<CandidateDetail> editCandidate(
    String id,
    Map<String, dynamic> changes,
  ) => _authed((token) => _client.editCandidate(token, id, changes));

  Future<void> confirmCandidate(
    String id,
    int version, {
    required String accountId,
    String? categoryId,
    String? destinationAccountId,
  }) => _authed(
    (token) => _client.confirmCandidate(
      accessToken: token,
      candidateId: id,
      version: version,
      accountId: accountId,
      categoryId: categoryId,
      destinationAccountId: destinationAccountId,
    ),
  );

  Future<void> rejectCandidate(String id, int version) => _authed(
    (token) => _client.rejectCandidate(
      accessToken: token,
      candidateId: id,
      version: version,
    ),
  );

  Future<List<LedgerAccount>> accounts() => _authed(_client.accounts);

  Future<LedgerAccount> createAccount({
    required String name,
    required String kind,
    required String currency,
    int? minorUnit,
    String? unit,
    String? idempotencyKey,
  }) => _authed(
    (token) => _client.createAccount(
      accessToken: token,
      name: name,
      kind: kind,
      currency: currency,
      minorUnit: minorUnit,
      unit: unit,
      idempotencyKey: idempotencyKey,
    ),
  );

  Future<List<SpendingCategory>> categories() => _authed(_client.categories);
  Future<SpendingCategory> createCategory({
    required String name,
    required String type,
    int? budgetAtomic,
  }) => _authed(
    (token) => _client.createCategory(
      accessToken: token,
      name: name,
      type: type,
      budgetAtomic: budgetAtomic,
    ),
  );
  Future<SpendingCategory> updateCategoryBudget({
    required String id,
    int? budgetAtomic,
  }) => _authed(
    (token) => _client.updateCategoryBudget(
      accessToken: token,
      id: id,
      budgetAtomic: budgetAtomic,
    ),
  );
  Future<MonthlySpending> monthlySpending({String? month}) =>
      _authed((token) => _client.monthlySpending(token, month: month));

  Future<LedgerHistory> transactions({String? cursor}) =>
      _authed((token) => _client.transactions(token, cursor: cursor));

  Future<LedgerEntry> reverseTransaction({
    required String transactionId,
    required String reason,
    required String idempotencyKey,
  }) => _authed(
    (token) => _client.reverseTransaction(
      accessToken: token,
      transactionId: transactionId,
      reason: reason,
      idempotencyKey: idempotencyKey,
    ),
  );

  Future<List<AssetValuation>> valuations(String accountId) =>
      _authed((token) => _client.valuations(token, accountId));

  Future<AssetValuation> recordValuation({
    required String accountId,
    required int valueAtomic,
    String? quantity,
    DateTime? effectiveAt,
    required String idempotencyKey,
  }) => _authed(
    (token) => _client.recordValuation(
      accessToken: token,
      accountId: accountId,
      valueAtomic: valueAtomic,
      quantity: quantity,
      effectiveAt: effectiveAt,
      idempotencyKey: idempotencyKey,
    ),
  );

  /// [idempotencyKey] is generated by the caller and reused across retries, so
  /// a flaky connection cannot post the same money twice.
  Future<void> createTransaction({
    required String accountId,
    required String transactionType,
    String? categoryId,
    required int amountAtomic,
    required String description,
    String? direction,
    DateTime? occurredAt,
    required String idempotencyKey,
  }) => _authed(
    (token) => _client.createTransaction(
      accessToken: token,
      accountId: accountId,
      transactionType: transactionType,
      categoryId: categoryId,
      amountAtomic: amountAtomic,
      description: description,
      direction: direction,
      occurredAt: occurredAt,
      // Reused across the retry as well, so a token refresh in the
      // middle of posting money cannot create a second entry.
      idempotencyKey: idempotencyKey,
    ),
  );

  Future<LedgerEntry> correctBalance({
    required String accountId,
    required int balanceAtomic,
    required String idempotencyKey,
  }) => _authed(
    (token) => _client.correctBalance(
      accessToken: token,
      accountId: accountId,
      balanceAtomic: balanceAtomic,
      idempotencyKey: idempotencyKey,
    ),
  );

  Future<void> createTransfer({
    required String fromAccountId,
    required String toAccountId,
    required int amountAtomic,
    int? destinationAmountAtomic,
    DateTime? occurredAt,
    required String description,
    required String idempotencyKey,
  }) => _authed(
    (token) => _client.createTransfer(
      accessToken: token,
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      amountAtomic: amountAtomic,
      destinationAmountAtomic: destinationAmountAtomic,
      occurredAt: occurredAt,
      description: description,
      idempotencyKey: idempotencyKey,
    ),
  );

  Future<InboxAddress?> inboxAddress() => _authed(_client.inboxAddress);

  Future<InboxAddress> createInboxAddress() =>
      _authed(_client.createInboxAddress);

  Future<GmailConnection?> gmailConnection() =>
      _authed(_client.gmailConnection);

  Future<GmailSyncJob> requestGmailSync(int days) =>
      _authed((token) => _client.requestGmailSync(token, days));

  Future<GmailSyncJob> gmailSyncJob(String id) =>
      _authed((token) => _client.gmailSyncJob(token, id));

  Future<void> registerPushDevice(String token) async {
    final previous = _pushRegistration;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // A later token can still register after an earlier failure.
      }
    }
    final registration = _authed(
      (accessToken) => _client.registerPushDevice(accessToken, token),
    );
    _pushRegistration = registration;
    try {
      await registration;
      _registeredPushToken = token;
    } finally {
      if (identical(_pushRegistration, registration)) _pushRegistration = null;
    }
  }

  Future<void> unregisterPushDevice(String token) => _authed(
    (accessToken) => _client.unregisterPushDevice(accessToken, token),
  );

  Future<Uri> connectGmail() => _authed(_client.connectGmail);

  Future<void> disconnectGmail() => _authed(_client.disconnectGmail);

  Future<HouseholdPeople> people() => _authed(_client.people);

  Future<Object?> locationRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) => _authed(
    (token) => _client.locationRequest(method, path, token, body: body),
  );

  Future<Object?> listsRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) =>
      _authed((token) => _client.listsRequest(method, path, token, body: body));

  Future<void> invite({required String email, required String role}) => _authed(
    (token) => _client.invite(accessToken: token, email: email, role: role),
  );

  Future<void> revokeInvite(String inviteId) => _authed(
    (token) => _client.revokeInvite(accessToken: token, inviteId: inviteId),
  );

  Future<void> signOut() async {
    try {
      await const MethodChannel('rumpun/location').invokeMethod('stop');
    } on MissingPluginException {
      debugPrint('Native location service unavailable on this platform.');
    } on PlatformException {
      debugPrint(
        'Native location shutdown failed; server expiry remains enforced.',
      );
    }
    final registration = _pushRegistration;
    if (registration != null) {
      try {
        await registration;
      } catch (_) {
        // Sign-out still clears the local session after a failed registration.
      }
    }
    final pushToken = _registeredPushToken;
    if (pushToken != null && _session != null) {
      try {
        await unregisterPushDevice(pushToken);
      } catch (_) {
        // A failed unregister is retried when this device signs in again.
      }
    }
    _registeredPushToken = null;
    final stored = await _store.read();
    if (stored != null) {
      try {
        await _client.logout(stored);
      } on ApiException {
        // The server already considers the session gone; clear ours regardless.
      } on NetworkException {
        // Offline sign-out still has to clear local credentials.
      }
    }
    await _store.clear();
    if (_googleReady) {
      await _google.signOut();
    }
    _session = null;
    notifyListeners();
  }
}
