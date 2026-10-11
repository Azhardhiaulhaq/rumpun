import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, SocketException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

/// Android emulators reach the host machine through 10.0.2.2 rather than
/// localhost, which resolves to the emulator itself.
String _defaultBaseUrl() {
  const fromEnv = String.fromEnvironment('RUMPUN_API_BASE_URL');
  if (fromEnv.isNotEmpty) return fromEnv;
  if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:8000/api/v1';
  return 'http://localhost:8000/api/v1';
}

class ApiClient {
  ApiClient({String? baseUrl, http.Client? httpClient})
    : baseUrl = baseUrl ?? _defaultBaseUrl(),
      _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  static const _timeout = Duration(seconds: 20);

  String get _pushPlatform => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'ios',
    TargetPlatform.android => 'android',
    _ => throw UnsupportedError('Push registration requires iOS or Android.'),
  };

  Future<Object?> locationRequest(
    String method,
    String path,
    String accessToken, {
    Map<String, dynamic>? body,
  }) => _raw(method, '/location$path', body, accessToken: accessToken);

  Future<Object?> listsRequest(
    String method,
    String path,
    String accessToken, {
    Map<String, dynamic>? body,
  }) => _raw(method, '/lists$path', body, accessToken: accessToken);

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) => _send('POST', path, body, accessToken: accessToken);

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) => _send('PATCH', path, body, accessToken: accessToken);

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic>? body, {
    String? accessToken,
    Map<String, String>? extraHeaders,
  }) async {
    final decoded = await _raw(
      method,
      path,
      body,
      accessToken: accessToken,
      extraHeaders: extraHeaders,
    );
    return decoded is Map<String, dynamic> ? decoded : const {};
  }

  Future<List<dynamic>> _sendList(
    String method,
    String path,
    String? accessToken,
  ) async {
    final decoded = await _raw(method, path, null, accessToken: accessToken);
    return decoded is List<dynamic> ? decoded : const [];
  }

  Future<Object?> _raw(
    String method,
    String path,
    Map<String, dynamic>? body, {
    String? accessToken,
    Map<String, String>? extraHeaders,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Content-Type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        ...?extraHeaders,
      });
    if (body != null) request.body = jsonEncode(body);

    http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(_timeout),
      ).timeout(_timeout);
    } on SocketException {
      throw const NetworkException('Tidak bisa menghubungi server Rumpun.');
    } on TimeoutException {
      throw const NetworkException('Server Rumpun tidak merespons.');
    } on http.ClientException catch (error) {
      throw NetworkException(error.message);
    }

    if (response.statusCode == 204 || response.body.isEmpty) {
      return const <String, dynamic>{};
    }

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw NetworkException(
        'Server mengirim balasan yang tidak dikenali (${response.statusCode}).',
      );
    }

    if (response.statusCode >= 400) {
      final error = decoded is Map<String, dynamic> ? decoded['error'] : null;
      if (error is Map<String, dynamic>) {
        throw ApiException(
          statusCode: response.statusCode,
          code: error['code'] as String? ?? 'unknown_error',
          message: error['message'] as String? ?? 'Terjadi kesalahan.',
        );
      }
      throw ApiException(
        statusCode: response.statusCode,
        code: 'unknown_error',
        message: 'Terjadi kesalahan (${response.statusCode}).',
      );
    }
    return decoded;
  }

  Future<AuthSession> register({
    required String email,
    required String password,
    required String displayName,
  }) async => AuthSession.fromJson(
    await post('/auth/register', {
      'email': email,
      'password': password,
      'display_name': displayName,
    }),
  );

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async => AuthSession.fromJson(
    await post('/auth/login', {'email': email, 'password': password}),
  );

  Future<AuthSession> loginWithGoogle(String idToken) async =>
      AuthSession.fromJson(await post('/auth/google', {'id_token': idToken}));

  Future<AuthSession> refresh(String refreshToken) async =>
      AuthSession.fromJson(
        await post('/auth/refresh', {'refresh_token': refreshToken}),
      );

  Future<void> logout(String refreshToken) =>
      post('/auth/logout', {'refresh_token': refreshToken});

  Future<HouseholdContext> household(String accessToken) async =>
      HouseholdContext.fromJson(
        await _send('GET', '/household', null, accessToken: accessToken),
      );

  Future<HouseholdContext> updateHousehold({
    required String accessToken,
    required String name,
    required String baseCurrency,
  }) async => HouseholdContext.fromJson(
    await patch('/household', {
      'name': name,
      'base_currency': baseCurrency,
    }, accessToken: accessToken),
  );

  Future<HouseholdContext> createHousehold({
    required String accessToken,
    required String name,
    required String baseCurrency,
  }) async => HouseholdContext.fromJson(
    await post('/onboarding/household', {
      'name': name,
      'base_currency': baseCurrency,
    }, accessToken: accessToken),
  );

  Future<List<InviteSummary>> myInvites(String accessToken) async {
    final body = await _sendList('GET', '/onboarding/invites', accessToken);
    return [
      for (final invite in body)
        InviteSummary.fromJson(invite as Map<String, dynamic>),
    ];
  }

  Future<HouseholdContext> acceptInvite({
    required String accessToken,
    required String inviteId,
  }) async => HouseholdContext.fromJson(
    await post(
      '/onboarding/invites/$inviteId/accept',
      const {},
      accessToken: accessToken,
    ),
  );

  Future<void> declineInvite({
    required String accessToken,
    required String inviteId,
  }) => post(
    '/onboarding/invites/$inviteId/decline',
    const {},
    accessToken: accessToken,
  );

  Future<HouseholdPeople> people(String accessToken) async =>
      HouseholdPeople.fromJson(
        await _send('GET', '/household/people', null, accessToken: accessToken),
      );

  Future<void> invite({
    required String accessToken,
    required String email,
    required String role,
  }) => post('/household/invites', {
    'email': email,
    'role': role,
  }, accessToken: accessToken);

  Future<void> revokeInvite({
    required String accessToken,
    required String inviteId,
  }) => _send(
    'DELETE',
    '/household/invites/$inviteId',
    null,
    accessToken: accessToken,
  );

  Future<Dashboard> dashboard(String accessToken) async => Dashboard.fromJson(
    await _send('GET', '/dashboard', null, accessToken: accessToken),
  );

  Future<Trends> trends(
    String accessToken, {
    String granularity = 'week',
    int periods = 8,
    String? currency,
  }) async => Trends.fromJson(
    await _send(
      'GET',
      '/dashboard/trends?granularity=$granularity&periods=$periods${currency == null ? '' : '&currency=${Uri.encodeQueryComponent(currency)}'}',
      null,
      accessToken: accessToken,
    ),
  );

  Future<CandidateList> candidates(
    String accessToken, {
    String? state,
    String? cursor,
  }) async {
    final parameters = <String, String>{'limit': '100'};
    if (state != null) parameters['state'] = state;
    if (cursor != null) parameters['cursor'] = cursor;
    final query = Uri(queryParameters: parameters).query;
    return CandidateList.fromJson(
      await _send('GET', '/candidates?$query', null, accessToken: accessToken),
    );
  }

  Future<CandidateDetail> candidateDetail(
    String accessToken,
    String id,
  ) async => CandidateDetail.fromJson(
    await _send('GET', '/candidates/$id', null, accessToken: accessToken),
  );

  Future<CandidateDetail> editCandidate(
    String accessToken,
    String id,
    Map<String, dynamic> changes,
  ) async => CandidateDetail.fromJson(
    await _send('PATCH', '/candidates/$id', changes, accessToken: accessToken),
  );

  /// The key is derived from everything the request says, so a retry after a
  /// lost response replays the first posting instead of writing a second,
  /// while a different choice of account or category is a new request.
  Future<void> confirmCandidate({
    required String accessToken,
    required String candidateId,
    required int version,
    required String accountId,
    String? categoryId,
    String? destinationAccountId,
  }) => _send(
    'POST',
    '/candidates/$candidateId/confirm',
    {
      'version': version,
      'account_id': accountId,
      'category_id': ?categoryId,
      'destination_account_id': ?destinationAccountId,
    },
    accessToken: accessToken,
    extraHeaders: {
      'Idempotency-Key':
          'candidate-confirm-$candidateId-v$version-$accountId-${categoryId ?? ''}'
          '${destinationAccountId == null ? '' : '-$destinationAccountId'}',
    },
  );

  Future<void> rejectCandidate({
    required String accessToken,
    required String candidateId,
    required int version,
  }) => post('/candidates/$candidateId/reject', {
    'version': version,
  }, accessToken: accessToken);

  Future<List<LedgerAccount>> accounts(String accessToken) async => [
    for (final a in await _sendList('GET', '/accounts', accessToken))
      LedgerAccount.fromJson(a as Map<String, dynamic>),
  ];

  Future<LedgerAccount> createAccount({
    required String accessToken,
    required String name,
    required String kind,
    required String currency,
    int? minorUnit,
    String? unit,
    String? idempotencyKey,
  }) async => LedgerAccount.fromJson(
    await _send(
      'POST',
      '/accounts',
      {
        'name': name,
        'kind': kind,
        'currency': currency,
        'minor_unit': ?minorUnit,
        'unit': ?unit,
      },
      accessToken: accessToken,
      extraHeaders: {'Idempotency-Key': ?idempotencyKey},
    ),
  );

  Future<List<SpendingCategory>> categories(String accessToken) async => [
    for (final row in await _sendList('GET', '/categories', accessToken))
      SpendingCategory.fromJson(row as Map<String, dynamic>),
  ];

  Future<SpendingCategory> createCategory({
    required String accessToken,
    required String name,
    required String type,
    int? budgetAtomic,
  }) async => SpendingCategory.fromJson(
    await _send('POST', '/categories', {
      'name': name,
      'category_type': type,
      'budget_atomic': budgetAtomic,
    }, accessToken: accessToken),
  );

  Future<SpendingCategory> updateCategoryBudget({
    required String accessToken,
    required String id,
    int? budgetAtomic,
  }) async => SpendingCategory.fromJson(
    await _send('PATCH', '/categories/$id/budget', {
      'budget_atomic': budgetAtomic,
    }, accessToken: accessToken),
  );

  Future<MonthlySpending> monthlySpending(
    String accessToken, {
    String? month,
  }) async => MonthlySpending.fromJson(
    await _send(
      'GET',
      '/dashboard/categories${month == null ? '' : '?month=$month'}',
      null,
      accessToken: accessToken,
    ),
  );

  Future<LedgerHistory> transactions(
    String accessToken, {
    String? cursor,
  }) async => LedgerHistory.fromJson(
    await _send(
      'GET',
      cursor == null
          ? '/transactions'
          : '/transactions?cursor=${Uri.encodeQueryComponent(cursor)}',
      null,
      accessToken: accessToken,
    ),
  );

  Future<LedgerEntry> reverseTransaction({
    required String accessToken,
    required String transactionId,
    required String reason,
    required String idempotencyKey,
  }) async => LedgerEntry.fromJson(
    await _send(
      'POST',
      '/transactions/$transactionId/reverse',
      {'reason': reason},
      accessToken: accessToken,
      extraHeaders: {'Idempotency-Key': idempotencyKey},
    ),
  );

  Future<List<AssetValuation>> valuations(
    String accessToken,
    String accountId,
  ) async => [
    for (final row in await _sendList(
      'GET',
      '/accounts/$accountId/valuations',
      accessToken,
    ))
      AssetValuation.fromJson(row as Map<String, dynamic>),
  ];

  Future<AssetValuation> recordValuation({
    required String accessToken,
    required String accountId,
    required int valueAtomic,
    String? quantity,
    DateTime? effectiveAt,
    required String idempotencyKey,
  }) async => AssetValuation.fromJson(
    await _send(
      'POST',
      '/accounts/$accountId/valuations',
      {
        'value_atomic': valueAtomic,
        'quantity': ?quantity,
        if (effectiveAt != null)
          'effective_at': effectiveAt.toUtc().toIso8601String(),
      },
      accessToken: accessToken,
      extraHeaders: {'Idempotency-Key': idempotencyKey},
    ),
  );

  Future<void> createTransaction({
    required String accessToken,
    required String accountId,
    required String transactionType,
    String? categoryId,
    required int amountAtomic,
    required String description,
    String? direction,
    DateTime? occurredAt,
    required String idempotencyKey,
  }) => _send(
    'POST',
    '/transactions',
    {
      'account_id': accountId,
      'transaction_type': transactionType,
      'category_id': ?categoryId,
      'amount_atomic': amountAtomic,
      'description': description,
      'direction': ?direction,
      if (occurredAt != null)
        'occurred_at': occurredAt.toUtc().toIso8601String(),
    },
    accessToken: accessToken,
    extraHeaders: {'Idempotency-Key': idempotencyKey},
  );

  Future<LedgerEntry> correctBalance({
    required String accessToken,
    required String accountId,
    required int balanceAtomic,
    required String idempotencyKey,
  }) async => LedgerEntry.fromJson(
    await _send(
      'POST',
      '/accounts/$accountId/correct',
      {'balance_atomic': balanceAtomic},
      accessToken: accessToken,
      extraHeaders: {'Idempotency-Key': idempotencyKey},
    ),
  );

  Future<void> createTransfer({
    required String accessToken,
    required String fromAccountId,
    required String toAccountId,
    required int amountAtomic,
    int? destinationAmountAtomic,
    DateTime? occurredAt,
    required String description,
    required String idempotencyKey,
  }) => _send(
    'POST',
    '/transfers',
    {
      'from_account_id': fromAccountId,
      'to_account_id': toAccountId,
      'amount_atomic': amountAtomic,
      'destination_amount_atomic': ?destinationAmountAtomic,
      if (occurredAt != null)
        'occurred_at': occurredAt.toUtc().toIso8601String(),
      'description': description,
    },
    accessToken: accessToken,
    extraHeaders: {'Idempotency-Key': idempotencyKey},
  );

  Future<InboxAddress?> inboxAddress(String accessToken) async {
    final body = await _raw(
      'GET',
      '/inbox/address',
      null,
      accessToken: accessToken,
    );
    if (body == null) return null;
    return InboxAddress.fromJson(body as Map<String, dynamic>);
  }

  Future<InboxAddress> createInboxAddress(String accessToken) async =>
      InboxAddress.fromJson(
        await _send('POST', '/inbox/address', null, accessToken: accessToken),
      );

  Future<GmailConnection?> gmailConnection(String accessToken) async {
    final body = await _raw(
      'GET',
      '/gmail/connection',
      null,
      accessToken: accessToken,
    );
    if (body == null) return null;
    return GmailConnection.fromJson(body as Map<String, dynamic>);
  }

  Future<GmailSyncJob> requestGmailSync(String accessToken, int days) async =>
      GmailSyncJob.fromJson(
        await _send('POST', '/gmail/sync', {
          'days': days,
        }, accessToken: accessToken),
      );

  Future<GmailSyncJob> gmailSyncJob(String accessToken, String id) async =>
      GmailSyncJob.fromJson(
        await _send('GET', '/gmail/sync/$id', null, accessToken: accessToken),
      );

  Future<void> registerPushDevice(String accessToken, String token) async {
    await _send('POST', '/notifications/devices', {
      'token': token,
      'platform': _pushPlatform,
    }, accessToken: accessToken);
  }

  Future<void> unregisterPushDevice(String accessToken, String token) async {
    await _send('DELETE', '/notifications/devices', {
      'token': token,
      'platform': _pushPlatform,
    }, accessToken: accessToken);
  }

  Future<Uri> connectGmail(String accessToken) async {
    final body = await _send(
      'POST',
      '/gmail/connect',
      null,
      accessToken: accessToken,
    );
    return Uri.parse(body['authorization_url'] as String);
  }

  Future<void> disconnectGmail(String accessToken) async {
    await _send('DELETE', '/gmail/connection', null, accessToken: accessToken);
  }

  void close() => _http.close();
}
