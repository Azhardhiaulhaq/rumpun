import 'dart:convert';
import 'dart:io' show SocketException;

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
const bcaId = 'b0000000-0000-0000-0000-000000000001';
const jagoAzharId = 'b0000000-0000-0000-0000-000000000002';
const jagoLitaId = 'b0000000-0000-0000-0000-000000000003';
const inviteId = '33333333-3333-3333-3333-333333333333';
const invitingHousehold = 'Keluarga Budi';

Map<String, dynamic> _household({
  required bool isNamed,
  String role = 'owner',
}) => {
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
  String accessToken = 'access-token',
}) => {
  'access_token': accessToken,
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

http.Response _error(int status, String code, String message) => _json({
  'error': {'code': code, 'message': message, 'request_id': 'test'},
}, status);

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
    this.transactionHistory = const [],
    this.laterTransactionHistory = const [],
    this.inboxAddress,
    this.gmailConnection,
    this.gmailSyncResult,
    this.failTransactionWithCode,
    this.trendBuckets = const [],
    this.trendChangeBps,
    this.trendSpendChangeBps,
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
  final List<Map<String, dynamic>> transactionHistory;
  final List<Map<String, dynamic>> laterTransactionHistory;
  final Map<String, dynamic>? inboxAddress;
  final Map<String, dynamic>? gmailConnection;

  /// Overrides fields of the finished sync job the fake reports.
  final Map<String, dynamic>? gmailSyncResult;
  final String? failTransactionWithCode;
  final List<Map<String, dynamic>> trendBuckets;
  final int? trendChangeBps;
  final int? trendSpendChangeBps;

  /// Delay before every response, so tests can observe the in-flight state
  /// that an instant mock would skip past.
  Duration latency = Duration.zero;

  /// When true, every call carrying the current access token is rejected as
  /// expired until a refresh mints a new one. This is the ordinary state of an
  /// app left open longer than the access token's 15 minutes.
  bool accessTokenExpired = false;

  /// Set to reject the refresh itself, which is the only case that genuinely
  /// forces the household to sign in again.
  bool refreshTokenRejected = false;

  int refreshCalls = 0;
  int expiredCalls = 0;

  /// Bumped on every refresh so each round issues a distinguishable token, the
  /// way rotating tokens do on the real server.
  int _tokenGeneration = 0;

  String get currentAccessToken => 'access-token-$_tokenGeneration';

  Map<String, dynamic> _gmailSyncJob() => {
    'id': '99999999-9999-9999-9999-999999999999',
    'status': 'complete',
    'days': lastGmailSyncDays ?? 2,
    'discovered_count': 0,
    'candidate_count': 0,
    'unclassified_count': 0,
    'error_code': null,
    ...?gmailSyncResult,
  };

  Map<String, dynamic>? lastSetupBody;
  Map<String, dynamic>? lastInviteBody;
  int acceptCalls = 0;
  String? acceptedInviteId;
  String? declinedInviteId;
  String? revokedInviteId;
  Map<String, dynamic>? lastTransactionBody;
  Map<String, dynamic>? lastTransferBody;
  Map<String, dynamic>? lastAccountBody;
  Map<String, dynamic>? lastValuationBody;
  Map<String, dynamic>? lastReversalBody;
  final List<Map<String, dynamic>> createdAccounts = [];
  final List<Map<String, dynamic>> createdBalances = [];
  final List<Map<String, dynamic>> recordedValuations = [];
  int transactionListCalls = 0;
  String? lastTrendCurrency;
  final List<String> transactionKeys = [];
  bool inboxAddressCreated = false;
  bool gmailDisconnected = false;
  int? lastGmailSyncDays;
  Map<String, dynamic>? lastCandidateEditBody;
  Map<String, dynamic>? _currentGmail;
  Map<String, dynamic>? _currentInbox;
  String? confirmedCandidateId;
  String? confirmIdempotencyKey;
  Map<String, dynamic>? lastConfirmBody;
  String? rejectedCandidateId;

  /// When true every request fails the way a lost connection does, before any
  /// response exists to inspect.
  bool offline = false;

  http.Client build() => MockClient((request) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (offline) {
      throw const SocketException('No route to host');
    }
    final path = request.url.path;
    final method = request.method;

    if (path.endsWith('/auth/refresh')) {
      refreshCalls++;
      if (refreshTokenRejected) {
        return _error(401, 'invalid_refresh_token', 'Refresh ditolak.');
      }
      // A completed refresh is what makes the old access token stale, so
      // the expiry clears itself here rather than by a test flag.
      _tokenGeneration++;
      accessTokenExpired = false;
      return _json(
        tokenPayload(
          isNewUser: isNewUser,
          householdNamed: householdNamed,
          withHousehold: withHousehold,
          invites: invites,
          accessToken: currentAccessToken,
        ),
        200,
      );
    }

    // Mirrors the real dependency: the token is checked before the route
    // runs, so an expired one fails whatever it was asking for.
    if (accessTokenExpired &&
        request.headers['Authorization'] != null &&
        !path.endsWith('/auth/logout')) {
      expiredCalls++;
      return _error(401, 'invalid_token', 'Token kedaluwarsa.');
    }

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
      return _json([...accountList, ...createdAccounts], 200);
    }

    if (path.endsWith('/accounts') && method == 'POST') {
      lastAccountBody = jsonDecode(request.body) as Map<String, dynamic>;
      final currency = lastAccountBody!['currency'] as String;
      final id =
          'aaaaaaaa-aaaa-aaaa-aaaa-${createdAccounts.length.toString().padLeft(12, '0')}';
      final created = {
        'id': id,
        ...lastAccountBody!,
        'minor_unit':
            lastAccountBody!['minor_unit'] ??
            (const ['IDR', 'JPY', 'KRW'].contains(currency) ? 0 : 2),
        'visibility': 'household',
      };
      createdAccounts.add(created);
      createdBalances.add({
        'account_id': id,
        'name': created['name'],
        'kind': created['kind'],
        'currency': currency,
        'minor_unit': created['minor_unit'],
        'balance_atomic': 0,
      });
      return _json(created, 201);
    }

    if (path.endsWith('/categories') &&
        !path.endsWith('/dashboard/categories') &&
        method == 'GET') {
      return _json([
        {
          'id': 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
          'name': 'General expense',
          'category_type': 'expense',
          'budget_atomic': null,
        },
        {
          'id': 'ffffffff-ffff-ffff-ffff-ffffffffffff',
          'name': 'General income',
          'category_type': 'income',
          'budget_atomic': null,
        },
      ], 200);
    }
    if (path.endsWith('/dashboard/categories') && method == 'GET') {
      return _json({
        'month': '2026-08',
        'currency': 'IDR',
        'minor_unit': 0,
        'items': [],
      }, 200);
    }
    if (path.endsWith('/categories') && method == 'POST') {
      return _json({
        'id': 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
        ...jsonDecode(request.body) as Map<String, dynamic>,
      }, 201);
    }
    if (path.contains('/categories/') &&
        path.endsWith('/budget') &&
        method == 'PATCH') {
      return _json({
        'id': 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
        'name': 'General expense',
        'category_type': 'expense',
        ...jsonDecode(request.body) as Map<String, dynamic>,
      }, 200);
    }
    if (path.endsWith('/transactions') && method == 'GET') {
      transactionListCalls++;
      return _json({
        'items': request.url.queryParameters.containsKey('cursor')
            ? laterTransactionHistory
            : transactionHistory,
        'next_cursor':
            request.url.queryParameters.containsKey('cursor') ||
                laterTransactionHistory.isEmpty
            ? null
            : 'older-page',
      }, 200);
    }

    if (path.contains('/accounts/') &&
        path.endsWith('/correct') &&
        method == 'POST') {
      return _json({
        'id': 'dddddddd-dddd-dddd-dddd-dddddddddddd',
        'transaction_type': 'adjustment',
        'status': 'posted',
        'description': 'Koreksi saldo',
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
        'amount_atomic': 1,
        'currency': 'IDR',
        'direction': 'in',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }, 201);
    }
    if (path.contains('/accounts/') &&
        path.endsWith('/valuations') &&
        method == 'GET') {
      final accountId = path.split('/')[path.split('/').length - 2];
      return _json([
        for (final value in recordedValuations)
          if (value['account_id'] == accountId) value,
      ], 200);
    }

    if (path.contains('/accounts/') &&
        path.endsWith('/valuations') &&
        method == 'POST') {
      lastValuationBody = jsonDecode(request.body) as Map<String, dynamic>;
      final accountId = path.split('/')[path.split('/').length - 2];
      final account = [
        ...accountList,
        ...createdAccounts,
      ].firstWhere((a) => a['id'] == accountId);
      final value = {
        'id': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'account_id': accountId,
        'value_atomic': lastValuationBody!['value_atomic'],
        'currency': account['currency'],
        'minor_unit': account['minor_unit'],
        'quantity': lastValuationBody!['quantity'],
        'unit': account['unit'],
        'effective_at':
            lastValuationBody!['effective_at'] ??
            DateTime.now().toUtc().toIso8601String(),
        'source': 'manual',
      };
      recordedValuations.add(value);
      final balance = createdBalances
          .where((a) => a['account_id'] == accountId)
          .firstOrNull;
      if (balance != null) {
        balance['balance_atomic'] = value['value_atomic'];
        balance['quantity'] = value['quantity'];
        balance['unit'] = value['unit'];
        balance['valued_at'] = value['effective_at'];
      }
      return _json(value, 201);
    }

    if (path.contains('/transactions/') &&
        path.endsWith('/reverse') &&
        method == 'POST') {
      lastReversalBody = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({
        ...transactionHistory.first,
        'id': 'cccccccc-cccc-cccc-cccc-cccccccccccc',
        'transaction_type': 'reversal',
        'reverses_transaction_id': transactionHistory.first['id'],
      }, 201);
    }

    if (path.endsWith('/transactions') && method == 'POST') {
      // Recorded before the failure branch, so a test can assert that a
      // retry reused the key rather than minting a new one.
      transactionKeys.add(request.headers['Idempotency-Key'] ?? '');
      if (failTransactionWithCode != null) {
        return _error(422, failTransactionWithCode!, 'Rejected');
      }
      lastTransactionBody = jsonDecode(request.body) as Map<String, dynamic>;
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

    if (path.endsWith('/gmail/connection') && method == 'GET') {
      final body = gmailDisconnected
          ? null
          : (_currentGmail ?? gmailConnection);
      return body == null ? http.Response('null', 200) : _json(body, 200);
    }

    if (path.endsWith('/gmail/sync') && method == 'POST') {
      lastGmailSyncDays =
          (jsonDecode(request.body) as Map<String, dynamic>)['days'] as int;
      return _json(_gmailSyncJob(), 200);
    }

    if (path.contains('/gmail/sync/') && method == 'GET') {
      return _json(_gmailSyncJob(), 200);
    }

    if (path.endsWith('/gmail/connect') && method == 'POST') {
      return _json({
        'authorization_url': 'https://accounts.google.com/o/oauth2/v2/auth',
      }, 200);
    }

    if (path.endsWith('/gmail/connection') && method == 'DELETE') {
      gmailDisconnected = true;
      _currentGmail = null;
      return http.Response('', 204);
    }

    if (failWithCode != null) {
      return _error(401, failWithCode!, 'Ditolak oleh server uji.');
    }
    if (path.endsWith('/dashboard/trends') && method == 'GET') {
      if (failDashboardWithCode != null) {
        return _error(503, failDashboardWithCode!, 'Trends failed');
      }
      lastTrendCurrency = request.url.queryParameters['currency'];
      return _json({
        'currency': lastTrendCurrency ?? 'IDR',
        'granularity': 'week',
        'buckets': trendBuckets,
        'change_bps': trendChangeBps,
        'spend_change_bps': trendSpendChangeBps,
      }, 200);
    }

    if (path.endsWith('/dashboard') && method == 'GET') {
      if (failDashboardWithCode != null) {
        return _error(503, failDashboardWithCode!, 'Dashboard failed');
      }
      // The backend derives the totals from postings, so the fake does the
      // same arithmetic rather than letting a test state it separately.
      // Equity is excluded for the same reason it is there: it balances
      // every entry, so counting it would net the household to zero.
      final totals = <String, int>{'IDR': 0};
      for (final a in [...accounts, ...createdBalances]) {
        if (a['kind'] == 'equity') continue;
        final currency = a['currency'] as String;
        totals[currency] =
            (totals[currency] ?? 0) + (a['balance_atomic'] as int);
      }
      return _json({
        'household': _household(isNamed: householdNamed),
        'totals_by_currency': totals,
        'accounts': [...accounts, ...createdBalances],
        'recent_transactions': recent,
      }, 200);
    }

    if (path.endsWith('/candidates') && method == 'GET') {
      final start =
          int.tryParse(request.url.queryParameters['cursor'] ?? '0') ?? 0;
      final limit =
          int.tryParse(request.url.queryParameters['limit'] ?? '20') ?? 20;
      final page = candidates.skip(start).take(limit).toList();
      final next = start + page.length;
      return _json({
        'items': page,
        'next_cursor': next < candidates.length ? '$next' : null,
      }, 200);
    }

    if (path.contains('/candidates/') && method == 'GET') {
      final id = path.split('/').last;
      final match = candidates
          .where((candidate) => candidate['id'] == id)
          .firstOrNull;
      if (match == null) {
        return _error(404, 'candidate_not_found', 'Candidate was not found');
      }
      return _json({
        ...match,
        'source': {
          'provider': 'gmail',
          'provider_message_id': 'gmail-test-message',
          'sender_domain': 'jago.com',
          'received_at': DateTime.now().toUtc().toIso8601String(),
          'parser_version': 'test',
          'metadata': {
            'subject':
                'You have made a payment to ${match['recipient_name'] ?? match['proposed']['description']}',
            'issuer': 'Jago',
          },
        },
        'warnings': <String>[],
        'evidence': <Object>[],
        'ledger_transaction_id': null,
      }, 200);
    }

    if (path.contains('/candidates/') && method == 'PATCH') {
      lastCandidateEditBody = jsonDecode(request.body) as Map<String, dynamic>;
      final id = path.split('/').last;
      final match = candidates.where((item) => item['id'] == id).firstOrNull;
      if (match == null) {
        return _error(404, 'candidate_not_found', 'Candidate was not found');
      }
      match['proposed'] = {
        ...match['proposed'] as Map<String, dynamic>,
        ...lastCandidateEditBody!,
      };
      match['version'] = (match['version'] as int) + 1;
      return _json({
        ...match,
        'source': {
          'provider': 'gmail',
          'provider_message_id': 'gmail-test-message',
          'sender_domain': 'jago.com',
          'received_at': DateTime.now().toUtc().toIso8601String(),
          'parser_version': 'test',
          'metadata': <String, dynamic>{},
        },
        'warnings': <String>[],
        'evidence': <Object>[],
        'ledger_transaction_id': null,
      }, 200);
    }

    if (path.contains('/candidates/') && path.endsWith('/confirm')) {
      confirmedCandidateId = _inviteIdIn(path);
      confirmIdempotencyKey = request.headers['Idempotency-Key'];
      lastConfirmBody = jsonDecode(request.body) as Map<String, dynamic>;
      // The same checks, in the same order, as candidates.confirm_candidate.
      if (confirmIdempotencyKey == null || confirmIdempotencyKey!.isEmpty) {
        return _json({
          'error': {
            'code': 'idempotency_key_required',
            'message': 'A valid Idempotency-Key is required',
          },
        }, 400);
      }
      if (lastConfirmBody!['account_id'] == null) {
        return _json({
          'error': {
            'code': 'candidate_account_required',
            'message': 'Choose the account that paid',
          },
        }, 422);
      }
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
  List<Map<String, dynamic>> transactionHistory = const [],
  List<Map<String, dynamic>> laterTransactionHistory = const [],
  Map<String, dynamic>? inboxAddress,
  Map<String, dynamic>? gmailConnection,
  Map<String, dynamic>? gmailSyncResult,
  String? failTransactionWithCode,
  List<Map<String, dynamic>> trendBuckets = const [],
  int? trendChangeBps,
  int? trendSpendChangeBps,
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
    transactionHistory: transactionHistory,
    laterTransactionHistory: laterTransactionHistory,
    inboxAddress: inboxAddress,
    gmailConnection: gmailConnection,
    gmailSyncResult: gmailSyncResult,
    failTransactionWithCode: failTransactionWithCode,
    trendBuckets: trendBuckets,
    trendChangeBps: trendChangeBps,
    trendSpendChangeBps: trendSpendChangeBps,
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
  List<Map<String, dynamic>> transactionHistory = const [],
  List<Map<String, dynamic>> laterTransactionHistory = const [],
  Map<String, dynamic>? inboxAddress,
  Map<String, dynamic>? gmailConnection,
  Map<String, dynamic>? gmailSyncResult,
  String? failTransactionWithCode,
  List<Map<String, dynamic>> trendBuckets = const [],
  int? trendChangeBps,
  int? trendSpendChangeBps,
}) => fakeAuth(
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
  transactionHistory: transactionHistory,
  laterTransactionHistory: laterTransactionHistory,
  inboxAddress: inboxAddress,
  gmailConnection: gmailConnection,
  gmailSyncResult: gmailSyncResult,
  failTransactionWithCode: failTransactionWithCode,
  trendBuckets: trendBuckets,
  trendChangeBps: trendChangeBps,
  trendSpendChangeBps: trendSpendChangeBps,
).repository;

/// One week on the home charts, shaped like the real endpoint's bucket.
Map<String, dynamic> trendBucket({
  required String start,
  required String label,
  int spent = 0,
  int received = 0,
  required int netWorth,
  bool complete = true,
}) => {
  'start': start,
  'end': start,
  'label': label,
  'spent_atomic': spent,
  'received_atomic': received,
  'net_worth_atomic': netWorth,
  'complete': complete,
};

Map<String, dynamic> member({
  required String name,
  required String email,
  String role = 'member',
  bool isYou = false,
}) => {
  'user_id': '55555555-5555-5555-5555-55555555555$role'.substring(0, 36),
  'display_name': name,
  'email': email,
  'role': role,
  'is_you': isYou,
};

Map<String, dynamic> openInvite({
  required String email,
  String role = 'member',
}) => {
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

int _accountSeq = 0;

Map<String, dynamic> account({
  required String name,
  required int balance,
  String kind = 'cash',
  String currency = 'IDR',
}) {
  // Ids have to differ: a screen that keys widgets by account id would
  // collapse several accounts into one if the fake reused a single id.
  final id = (_accountSeq++).toRadixString(16).padLeft(12, '0');
  return {
    'account_id': '66666666-6666-6666-6666-$id',
    'name': name,
    'kind': kind,
    'currency': currency,
    'balance_atomic': balance,
  };
}

Map<String, dynamic> ledgerEntry({
  required String description,
  required int amount,
  String type = 'expense',
  String currency = 'IDR',
  DateTime? at,
}) => {
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
  String? recipientName,
  String? recipientAccount,
  String? direction = 'expense',
  String? issuer,
  String? accountId,
  String? destinationAccountId,
  String? categoryId,
  List<String> suggestedFields = const [],
}) => {
  'id': id,
  'state': state,
  'version': version,
  'confidence_bps': confidenceBps,
  'recipient_name': recipientName,
  'recipient_account': recipientAccount,
  'direction': direction,
  'issuer': issuer,
  'suggested_fields': suggestedFields,
  'proposed': {
    'account_id': accountId,
    'amount_atomic': amount,
    'currency': 'IDR',
    'description': description,
    'occurred_at': DateTime.now().toUtc().toIso8601String(),
    'transaction_type': direction,
    'category_id': categoryId,
    'destination_account_id': destinationAccountId,
  },
  'created_at': DateTime.now().toUtc().toIso8601String(),
};

Map<String, dynamic> ledgerAccount({
  required String name,
  String id = '66666666-6666-6666-6666-666666666666',
  String kind = 'cash',
  String currency = 'IDR',
}) => {
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
}) => {
  'address': address,
  'state': state,
  'verification_code': verificationCode,
  'message_count': messageCount,
  'last_message_at': null,
  'created_at': DateTime.now().toUtc().toIso8601String(),
};
