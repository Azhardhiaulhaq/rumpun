import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'api_client.dart';
import 'models.dart';
import 'token_store.dart';

/// Web client ID from Google Cloud Console. The backend verifies the ID token's
/// `aud` against this exact value, so the Android and iOS client IDs will not
/// work here.
const _googleServerClientId = String.fromEnvironment('RUMPUN_GOOGLE_CLIENT_ID');

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
  })  : _client = client ?? ApiClient(),
        _store = store ?? const SecureTokenStore(),
        _google = google ?? const PluginGoogleAuthenticator(),
        _googleConfigured =
            googleConfigured ?? _googleServerClientId.isNotEmpty;

  final ApiClient _client;
  final TokenStore _store;
  final GoogleAuthenticator _google;
  final bool _googleConfigured;

  AuthSession? _session;
  bool _googleReady = false;

  AuthSession? get session => _session;
  bool get isSignedIn => _session != null;
  bool get isConfigured => _googleConfigured;

  /// True when the signed-in user has not joined a household yet.
  bool get needsOnboarding => _session?.needsOnboarding ?? false;

  /// True when the signed-in owner still has to name their household.
  bool get needsHouseholdSetup => _session?.needsHouseholdSetup ?? false;

  List<InviteSummary> get pendingInvites =>
      _session?.pendingInvites ?? const [];

  Future<void> _ensureGoogleInitialized() async {
    if (_googleReady) return;
    await _google.initialize(_googleServerClientId);
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

  /// Starts a household with this user as its owner.
  Future<void> createHousehold({
    required String name,
    required String baseCurrency,
  }) async {
    final current = _requireSession();
    _session = current.withHousehold(await _client.createHousehold(
      accessToken: current.accessToken,
      name: name,
      baseCurrency: baseCurrency,
    ));
    notifyListeners();
  }

  /// Joins the household that invited this email address.
  Future<void> acceptInvite(String inviteId) async {
    final current = _requireSession();
    _session = current.withHousehold(await _client.acceptInvite(
      accessToken: current.accessToken,
      inviteId: inviteId,
    ));
    notifyListeners();
  }

  /// Turns down an invitation, leaving the user free to start their own.
  Future<void> declineInvite(String inviteId) async {
    final current = _requireSession();
    await _client.declineInvite(
      accessToken: current.accessToken,
      inviteId: inviteId,
    );
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
    final current = _requireSession();
    _session = current.withHousehold(await _client.updateHousehold(
      accessToken: current.accessToken,
      name: name,
      baseCurrency: baseCurrency,
    ));
    notifyListeners();
  }

  Future<Dashboard> dashboard() async =>
      _client.dashboard(_requireSession().accessToken);

  Future<CandidateList> candidates() async =>
      _client.candidates(_requireSession().accessToken);

  Future<void> confirmCandidate(String id, int version) =>
      _client.confirmCandidate(
        accessToken: _requireSession().accessToken,
        candidateId: id,
        version: version,
      );

  Future<void> rejectCandidate(String id, int version) =>
      _client.rejectCandidate(
        accessToken: _requireSession().accessToken,
        candidateId: id,
        version: version,
      );

  Future<List<LedgerAccount>> accounts() async =>
      _client.accounts(_requireSession().accessToken);

  /// [idempotencyKey] is generated by the caller and reused across retries, so
  /// a flaky connection cannot post the same money twice.
  Future<void> createTransaction({
    required String accountId,
    required String transactionType,
    required int amountAtomic,
    required String description,
    required String idempotencyKey,
  }) =>
      _client.createTransaction(
        accessToken: _requireSession().accessToken,
        accountId: accountId,
        transactionType: transactionType,
        amountAtomic: amountAtomic,
        description: description,
        idempotencyKey: idempotencyKey,
      );

  Future<void> createTransfer({
    required String fromAccountId,
    required String toAccountId,
    required int amountAtomic,
    required String description,
    required String idempotencyKey,
  }) =>
      _client.createTransfer(
        accessToken: _requireSession().accessToken,
        fromAccountId: fromAccountId,
        toAccountId: toAccountId,
        amountAtomic: amountAtomic,
        description: description,
        idempotencyKey: idempotencyKey,
      );

  Future<InboxAddress?> inboxAddress() async =>
      _client.inboxAddress(_requireSession().accessToken);

  Future<InboxAddress> createInboxAddress() async =>
      _client.createInboxAddress(_requireSession().accessToken);

  Future<HouseholdPeople> people() async =>
      _client.people(_requireSession().accessToken);

  Future<void> invite({required String email, required String role}) =>
      _client.invite(
        accessToken: _requireSession().accessToken,
        email: email,
        role: role,
      );

  Future<void> revokeInvite(String inviteId) => _client.revokeInvite(
        accessToken: _requireSession().accessToken,
        inviteId: inviteId,
      );

  Future<void> signOut() async {
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
