import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rumpun_frontend/api/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final (target, expected) in [
    (TargetPlatform.iOS, 'ios'),
    (TargetPlatform.android, 'android'),
  ]) {
    test('push registration uses $expected for both requests', () async {
      debugDefaultTargetPlatformOverride = target;
      final requests = <http.Request>[];
      final client = ApiClient(
        baseUrl: 'https://example.test/api/v1',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('', 204);
        }),
      );

      await client.registerPushDevice('access-token', 'device-token');
      await client.unregisterPushDevice('access-token', 'device-token');

      expect(requests.map((request) => request.method), ['POST', 'DELETE']);
      for (final request in requests) {
        expect(request.url.path, '/api/v1/notifications/devices');
        expect(request.headers['authorization'], 'Bearer access-token');
        expect(jsonDecode(request.body), {
          'token': 'device-token',
          'platform': expected,
        });
      }
    });
  }
}
