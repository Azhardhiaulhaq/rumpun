import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rumpun_frontend/api/api_client.dart';
import 'package:rumpun_frontend/api/auth_repository.dart';
import 'package:rumpun_frontend/api/token_store.dart';

const signedInEmail = 'ratna@rumpun.app';
const signedInName = 'Ibu Ratna';
const generatedHouseholdName = 'Rumah Ibu Ratna';
const namedHousehold = 'Keluarga Santoso';

/// Stands in for the plugin so tests never touch a platform channel.
class FakeGoogle implements GoogleAuthenticator {
  FakeGoogle({this.idToken = 'google-id-token', this.error});

  final String? idToken;
  final Object? error;

  bool initialized = false;
  int authenticateCalls = 0;
  int signOutCalls = 0;

  @override
  Future<void> initialize(String serverClientId) async => initialized = true;

  @override
  Future<String?> authenticateAndGetIdToken() async {
    authenticateCalls++;
    if (error != null) throw error!;
    return idToken;
  }

  @override
  Future<void> signOut() async => signOutCalls++;
}

const candidateId = '88888888-8888-8888-8888-888888888888';
const inviteId = '33333333-3333-3333-3333-333333333333';
const invitingHousehold = 'Keluarga Budi';

Map<String, dynamic> _household({
  required bool isNamed,
  String role = 'owner',
}) =>
    {
      'id': '22222222-2222-2222-2222-222222222222',
      'name': isNamed ? namedHousehold : generatedHouseholdName,
      'role': role,
      'base_currency': 'IDR',
      'is_named': isNamed,
    };

Map<String, dynamic> _invite() => {
      'id': inviteId,
      'household_name': invitingHousehold,
      'role': 'member',
      'invited_by_name': 'Budi',
      'created_at': '2026-01-01T00:00:00Z',
    };

Map<String, dynamic> tokenPayload({
  bool isNewUser = false,
  bool householdNamed = true,
  bool withHousehold = true,
  int invites = 0,
}) =>
    {
      'access_token': 'access-token',
      'refresh_token': 'refresh-token-that-is-long-enough-for-the-api',
      'token_type': 'bearer',
      'expires_in': 900,
      'user': {
        'id': '11111111-1111-1111-1111-111111111111',
        'email': signedInEmail,
        'display_name': signedInName,
      },
      'household': withHousehold ? _household(isNamed: householdNamed) : null,
      'is_new_user': isNewUser,
      'pending_invites': [for (var i = 0; i < invites; i++) _invite()],
    };

/// `.../onboarding/invites/<id>/accept` -> `<id>`
String _inviteIdIn(String path) {
  final parts = path.split('/');
  return parts[parts.length - 2];
}

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

http.Response _error(int status, String code, String message) => _json(
      {
        'error': {'code': code, 'message': message, 'request_id': 'test'}
      },
      status,
    );

/// Mirrors `src/backend/app/routers/auth.py` and `household.py` closely enough
/// that the UI exercises the same success and failure branches.
class FakeBackend {
  FakeBackend({
    this.isNewUser = false,
    this.householdNamed = true,
    this.withHousehold = true,
    this.invites = 0,
    this.failWithCode,
    this.failSetupWithCode,
    this.failInviteWithCode,
    this.members = const [],
    this.openInvites = const [],
    this.accounts = const [],
    this.recent = const [],
    this.candidates = const [],
    this.failDashboardWithCode,
    this.accountList = const [],
    this.inboxAddress,
    this.failTransactionWithCode,
  });

  final bool isNewUser;
  final bool householdNamed;
  final bool withHousehold;
  final int invites;
  final String? failWithCode;
  final String? failSetupWithCode;
  final String? failInviteWithCode;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> openInvites;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> recent;
  final List<Map<String, dynamic>> candidates;
  final String? failDashboardWithCode;
  final List<Map<String, dynamic>> accountList;
  final Map<String, dynamic>? inboxAddress;
  final String? failTransactionWithCode;

  /// Delay before every response, so tests can observe the in-flight state
  /// that an instant mock would skip past.
  Duration latency = Duration.zero;

  Map<String, dynamic>? lastSetupBody;
  Map<String, dynamic>? lastInviteBody;
  int acceptCalls = 0;
  String? acceptedInviteId;
  String? declinedInviteId;
  String? revokedInviteId;
  Map<String, dynamic>? lastTransactionBody;
  Map<String, dynamic>? lastTransferBody;
  final List<String> transactionKeys = [];
  bool inboxAddressCreated = false;
  Map<String, dynamic>? _currentInbox;
  String? confirmedCandidateId;
  String? rejectedCandidateId;

  http.Client build() => MockClient((request) async {
        if (latency > Duration.zero) await Future<void>.delayed(latency);
        final path = request.url.path;
        final method = request.method;

        if (path.endsWith('/onboarding/household') && method == 'POST') {
          if (failSetupWithCode != null) {
            return _error(422, failSetupWithCode!, 'Ditolak oleh server uji.');
          }
          lastSetupBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({
            'id': '22222222-2222-2222-2222-222222222222',
            'name': (lastSetupBody!['name'] as String).trim(),
            'role': 'owner',
            'base_currency': lastSetupBody!['base_currency'],
            'is_named': true,
          }, 201);
        }

        if (path.contains('/onboarding/invites/') && path.endsWith('/accept')) {
          if (failSetupWithCode != null) {
            return _error(409, failSetupWithCode!, 'Ditolak oleh server uji.');
          }
          acceptCalls++;
          acceptedInviteId = _inviteIdIn(path);
          return _json({
            'id': '44444444-4444-4444-4444-444444444444',
            'name': invitingHousehold,
            'role': 'member',
            'base_currency': 'IDR',
            'is_named': true,
          }, 200);
        }

        if (path.contains('/onboarding/invites/') && path.endsWith('/decline')) {
          declinedInviteId = _inviteIdIn(path);
          return http.Response('', 204);
        }

        if (path.endsWith('/household/people') && method == 'GET') {
          return _json({'members': members, 'invites': openInvites}, 200);
        }

        if (path.endsWith('/household/invites') && method == 'POST') {
          if (failInviteWithCode != null) {
            return _error(409, failInviteWithCode!, 'Ditolak oleh server uji.');
          }
          lastInviteBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({
            'id': inviteId,
            'email': lastInviteBody!['email'],
            'role': lastInviteBody!['role'],
            'state': 'pending',
            'created_at': '2026-01-01T00:00:00Z',
          }, 201);
        }

        if (path.contains('/household/invites/') && method == 'DELETE') {
          revokedInviteId = path.split('/').last;
          return http.Response('', 204);
        }

        if (path.endsWith('/household') && method == 'PATCH') {
          if (failSetupWithCode != null) {
            return _error(422, failSetupWithCode!, 'Ditolak oleh server uji.');
          }
          lastSetupBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({
            'id': '22222222-2222-2222-2222-222222222222',
            'name': (lastSetupBody!['name'] as String).trim(),
            'role': 'owner',
            'base_currency': lastSetupBody!['base_currency'],
            'is_named': true,
          }, 200);
        }

        if (path.endsWith('/accounts') && method == 'GET') {
          return _json(accountList, 200);
        }

        if (path.endsWith('/transactions') && method == 'POST') {
          // Recorded before the failure branch, so a test can assert that a
          // retry reused the key rather than minting a new one.
          transactionKeys.add(request.headers['Idempotency-Key'] ?? '');
          if (failTransactionWithCode != null) {
            return _error(422, failTransactionWithCode!, 'Rejected');
          }
          lastTransactionBody =
              jsonDecode(request.body) as Map<String, dynamic>;
          return _json({'id': '99999999-9999-9999-9999-999999999999'}, 201);
        }

        if (path.endsWith('/transfers') && method == 'POST') {
          if (failTransactionWithCode != null) {
            return _error(422, failTransactionWithCode!, 'Rejected');
          }
          lastTransferBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({'id': '99999999-9999-9999-9999-999999999999'}, 201);
        }

        if (path.endsWith('/inbox/address') && method == 'GET') {
          // The API answers null when no address exists yet, which is a
          // valid JSON body and not an error.
          final body = _currentInbox ?? inboxAddress;
          if (body == null) return http.Response('null', 200);
          return _json(body, 200);
        }

        if (path.endsWith('/inbox/address') && method == 'POST') {
          inboxAddressCreated = true;
          // Held so the reload after creating returns the new address, the
          // way the real API would.
          _currentInbox = inboxAddress ?? inboxAddressJson();
          return _json(_currentInbox!, 201);
        }

        if (failWithCode != null) {
          return _error(401, failWithCode!, 'Ditolak oleh server uji.');
        }
        if (path.endsWith('/dashboard') && method == 'GET') {
          if (failDashboardWithCode != null) {
            return _error(503, failDashboardWithCode!, 'Dashboard failed');
          }
          // The backend derives the total from postings, so the fake does the
          // same arithmetic rather than letting a test state it separately.
          var total = 0;
          for (final a in accounts) {
            if (a['currency'] == 'IDR') total += a['balance_atomic'] as int;
          }
          return _json({
            'household': _household(isNamed: householdNamed),
            'totals_by_currency': {'IDR': total},
            'accounts': accounts,
            'recent_transactions': recent,
          }, 200);
        }

        if (path.endsWith('/candidates') && method == 'GET') {
          return _json({'items': candidates, 'next_cursor': null}, 200);
        }

        if (path.contains('/candidates/') && path.endsWith('/confirm')) {
          confirmedCandidateId = _inviteIdIn(path);
          return _json({'candidate_id': confirmedCandidateId}, 200);
        }

        if (path.contains('/candidates/') && path.endsWith('/reject')) {
          rejectedCandidateId = _inviteIdIn(path);
          return _json({'id': rejectedCandidateId}, 200);
        }

        if (path.endsWith('/auth/logout')) return http.Response('', 204);

        return _json(
          tokenPayload(
            isNewUser: isNewUser,
            householdNamed: householdNamed,
            withHousehold: withHousehold,
            invites: invites,
          ),
          200,
        );
      });
}

class FakeAuth {
  FakeAuth(this.repository, this.google, this.backend);

  final AuthRepository repository;
  final FakeGoogle google;
  final FakeBackend backend;
}

FakeAuth fakeAuth({
  bool withStoredToken = false,
  bool isNewUser = false,
  bool householdNamed = true,
  bool withHousehold = true,
  int invites = 0,
  bool googleConfigured = true,
  String? failWithCode,
  String? failSetupWithCode,
  String? failInviteWithCode,
  String? googleIdToken = 'google-id-token',
  Object? googleError,
  List<Map<String, dynamic>> members = const [],
  List<Map<String, dynamic>> openInvites = const [],
  List<Map<String, dynamic>> accounts = const [],
  List<Map<String, dynamic>> recent = const [],
  List<Map<String, dynamic>> candidates = const [],
  String? failDashboardWithCode,
  List<Map<String, dynamic>> accountList = const [],
  Map<String, dynamic>? inboxAddress,
  String? failTransactionWithCode,
}) {
  final store = InMemoryTokenStore();
  if (withStoredToken) store.write('refresh-token-that-is-long-enough-for-api');

  final backend = FakeBackend(
    isNewUser: isNewUser,
    householdNamed: householdNamed,
    withHousehold: withHousehold,
    invites: invites,
    failWithCode: failWithCode,
    failSetupWithCode: failSetupWithCode,
    failInviteWithCode: failInviteWithCode,
    members: members,
    openInvites: openInvites,
    accounts: accounts,
    recent: recent,
    candidates: candidates,
    failDashboardWithCode: failDashboardWithCode,
    accountList: accountList,
    inboxAddress: inboxAddress,
    failTransactionWithCode: failTransactionWithCode,
  );
  final google = FakeGoogle(idToken: googleIdToken, error: googleError);

  return FakeAuth(
    AuthRepository(
      client: ApiClient(
        baseUrl: 'http://test.local/api/v1',
        httpClient: backend.build(),
      ),
      store: store,
      google: google,
      googleConfigured: googleConfigured,
    ),
    google,
    backend,
  );
}

/// Convenience for the many tests that only need the repository.
AuthRepository fakeRepository({
  bool withStoredToken = false,
  bool isNewUser = false,
  bool householdNamed = true,
  bool withHousehold = true,
  int invites = 0,
  bool googleConfigured = true,
  String? failWithCode,
  Object? googleError,
  List<Map<String, dynamic>> accounts = const [],
  List<Map<String, dynamic>> recent = const [],
  List<Map<String, dynamic>> candidates = const [],
  String? failDashboardWithCode,
  List<Map<String, dynamic>> accountList = const [],
  Map<String, dynamic>? inboxAddress,
  String? failTransactionWithCode,
}) =>
    fakeAuth(
      withStoredToken: withStoredToken,
      isNewUser: isNewUser,
      householdNamed: householdNamed,
      withHousehold: withHousehold,
      invites: invites,
      googleConfigured: googleConfigured,
      failWithCode: failWithCode,
      googleError: googleError,
      accounts: accounts,
      recent: recent,
      candidates: candidates,
      failDashboardWithCode: failDashboardWithCode,
      accountList: accountList,
      inboxAddress: inboxAddress,
      failTransactionWithCode: failTransactionWithCode,
    ).repository;

Map<String, dynamic> member({
  required String name,
  required String email,
  String role = 'member',
  bool isYou = false,
}) =>
    {
      'user_id': '55555555-5555-5555-5555-55555555555$role'.substring(0, 36),
      'display_name': name,
      'email': email,
      'role': role,
      'is_you': isYou,
    };

Map<String, dynamic> openInvite({
  required String email,
  String role = 'member',
}) =>
    {
      'id': inviteId,
      'email': email,
      'role': role,
      'created_at': '2026-01-01T00:00:00Z',
    };

/// Kept so tests can build a canceled-picker error without importing the plugin.
GoogleSignInException canceledPicker() => const GoogleSignInException(
      code: GoogleSignInExceptionCode.canceled,
      description: 'user canceled',
    );


Map<String, dynamic> account({
  required String name,
  required int balance,
  String kind = 'cash',
  String currency = 'IDR',
}) =>
    {
      'account_id': '66666666-6666-6666-6666-666666666666',
      'name': name,
      'kind': kind,
      'currency': currency,
      'balance_atomic': balance,
    };

Map<String, dynamic> ledgerEntry({
  required String description,
  required int amount,
  String type = 'expense',
  String currency = 'IDR',
  DateTime? at,
}) =>
    {
      'id': '77777777-7777-7777-7777-777777777777',
      'transaction_type': type,
      'description': description,
      'occurred_at': (at ?? DateTime.now()).toUtc().toIso8601String(),
      'amount_atomic': amount,
      'currency': currency,
    };

Map<String, dynamic> candidateJson({
  required String description,
  int? amount,
  String state = 'pending',
  int version = 1,
  int confidenceBps = 9000,
  String id = candidateId,
}) =>
    {
      'id': id,
      'state': state,
      'version': version,
      'confidence_bps': confidenceBps,
      'proposed': {
        'account_id': null,
        'amount_atomic': amount,
        'currency': 'IDR',
        'description': description,
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
      },
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };


Map<String, dynamic> ledgerAccount({
  required String name,
  String id = '66666666-6666-6666-6666-666666666666',
  String kind = 'cash',
  String currency = 'IDR',
}) =>
    {
      'id': id,
      'name': name,
      'kind': kind,
      'currency': currency,
      'visibility': 'household',
    };

Map<String, dynamic> inboxAddressJson({
  String address = 'rumpun-abc123@mail.example.com',
  String state = 'pending_verification',
  String? verificationCode,
  int messageCount = 0,
}) =>
    {
      'address': address,
      'state': state,
      'verification_code': verificationCode,
      'message_count': messageCount,
      'last_message_at': null,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
