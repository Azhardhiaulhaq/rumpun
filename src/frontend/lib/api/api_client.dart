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

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) =>
      _send('POST', path, body, accessToken: accessToken);

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) =>
      _send('PATCH', path, body, accessToken: accessToken);

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic>? body, {
    String? accessToken,
    Map<String, String>? extraHeaders,
  }) async {
    final decoded = await _raw(method, path, body,
        accessToken: accessToken, extraHeaders: extraHeaders);
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
  }) async =>
      AuthSession.fromJson(await post('/auth/register', {
        'email': email,
        'password': password,
        'display_name': displayName,
      }));

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async =>
      AuthSession.fromJson(await post('/auth/login', {
        'email': email,
        'password': password,
      }));

  Future<AuthSession> loginWithGoogle(String idToken) async =>
      AuthSession.fromJson(await post('/auth/google', {'id_token': idToken}));

  Future<AuthSession> refresh(String refreshToken) async =>
      AuthSession.fromJson(await post('/auth/refresh', {
        'refresh_token': refreshToken,
      }));

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
  }) async =>
      HouseholdContext.fromJson(await patch(
        '/household',
        {'name': name, 'base_currency': baseCurrency},
        accessToken: accessToken,
      ));

  Future<HouseholdContext> createHousehold({
    required String accessToken,
    required String name,
    required String baseCurrency,
  }) async =>
      HouseholdContext.fromJson(await post(
        '/onboarding/household',
        {'name': name, 'base_currency': baseCurrency},
        accessToken: accessToken,
      ));

  Future<List<InviteSummary>> myInvites(String accessToken) async {
    final body = await _sendList('GET', '/onboarding/invites', accessToken);
    return [
      for (final invite in body)
        InviteSummary.fromJson(invite as Map<String, dynamic>)
    ];
  }

  Future<HouseholdContext> acceptInvite({
    required String accessToken,
    required String inviteId,
  }) async =>
      HouseholdContext.fromJson(await post(
        '/onboarding/invites/$inviteId/accept',
        const {},
        accessToken: accessToken,
      ));

  Future<void> declineInvite({
    required String accessToken,
    required String inviteId,
  }) =>
      post(
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
  }) =>
      post(
        '/household/invites',
        {'email': email, 'role': role},
        accessToken: accessToken,
      );

  Future<void> revokeInvite({
    required String accessToken,
    required String inviteId,
  }) =>
      _send('DELETE', '/household/invites/$inviteId', null,
          accessToken: accessToken);

  Future<Dashboard> dashboard(String accessToken) async => Dashboard.fromJson(
        await _send('GET', '/dashboard', null, accessToken: accessToken),
      );

  Future<CandidateList> candidates(String accessToken, {String? state}) async =>
      CandidateList.fromJson(await _send(
        'GET',
        state == null ? '/candidates' : '/candidates?state=$state',
        null,
        accessToken: accessToken,
      ));

  Future<void> confirmCandidate({
    required String accessToken,
    required String candidateId,
    required int version,
  }) =>
      post('/candidates/$candidateId/confirm', {'version': version},
          accessToken: accessToken);

  Future<void> rejectCandidate({
    required String accessToken,
    required String candidateId,
    required int version,
  }) =>
      post('/candidates/$candidateId/reject', {'version': version},
          accessToken: accessToken);

  Future<List<LedgerAccount>> accounts(String accessToken) async => [
        for (final a in await _sendList('GET', '/accounts', accessToken))
          LedgerAccount.fromJson(a as Map<String, dynamic>)
      ];

  Future<void> createTransaction({
    required String accessToken,
    required String accountId,
    required String transactionType,
    required int amountAtomic,
    required String description,
    required String idempotencyKey,
  }) =>
      _send(
        'POST',
        '/transactions',
        {
          'account_id': accountId,
          'transaction_type': transactionType,
          'amount_atomic': amountAtomic,
          'description': description,
        },
        accessToken: accessToken,
        extraHeaders: {'Idempotency-Key': idempotencyKey},
      );

  Future<void> createTransfer({
    required String accessToken,
    required String fromAccountId,
    required String toAccountId,
    required int amountAtomic,
    required String description,
    required String idempotencyKey,
  }) =>
      _send(
        'POST',
        '/transfers',
        {
          'from_account_id': fromAccountId,
          'to_account_id': toAccountId,
          'amount_atomic': amountAtomic,
          'description': description,
        },
        accessToken: accessToken,
        extraHeaders: {'Idempotency-Key': idempotencyKey},
      );

  Future<InboxAddress?> inboxAddress(String accessToken) async {
    final body = await _raw('GET', '/inbox/address', null,
        accessToken: accessToken);
    if (body == null) return null;
    return InboxAddress.fromJson(body as Map<String, dynamic>);
  }

  Future<InboxAddress> createInboxAddress(String accessToken) async =>
      InboxAddress.fromJson(
        await _send('POST', '/inbox/address', null, accessToken: accessToken),
      );

  void close() => _http.close();
}
