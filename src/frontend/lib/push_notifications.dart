import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api/auth_repository.dart';

/// Owns the Android token lifecycle while an authenticated household is open.
class PushNotifications {
  PushNotifications(
    this.auth, {
    required this.onReview,
    required this.onForeground,
  }) {
    auth.addListener(_sessionChanged);
    _tokenRefresh = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _token = token;
      _registeredFor = null;
      _registerIfReady();
    });
    _opened = FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
    _foreground = FirebaseMessaging.onMessage.listen(onForeground);
    _sessionChanged();
  }

  final AuthRepository auth;
  final void Function() onReview;
  final void Function(RemoteMessage) onForeground;
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<RemoteMessage>? _opened;
  StreamSubscription<RemoteMessage>? _foreground;
  String? _token;
  String? _registeredFor;
  bool _registering = false;
  bool _queuedRegistration = false;
  bool _started = false;

  void _sessionChanged() {
    if (auth.session?.household == null) {
      _registeredFor = null;
      return;
    }
    if (!_started) {
      _started = true;
      _start();
    } else {
      _registerIfReady();
    }
  }

  Future<void> _start() async {
    try {
      await FirebaseMessaging.instance.requestPermission();
      _token = await FirebaseMessaging.instance.getToken();
      _registerIfReady();
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _handleMessage(initial);
    } catch (error) {
      debugPrint('Push setup unavailable: ${error.runtimeType}');
    }
  }

  void _registerIfReady() {
    final session = auth.session;
    final token = _token;
    if (session?.household == null || token == null) return;
    if (_registering) {
      _queuedRegistration = true;
      return;
    }
    final key = '${session!.user.id}:${session.household!.id}:$token';
    if (key == _registeredFor) return;
    _registering = true;
    auth
        .registerPushDevice(token)
        .then((_) {
          _registeredFor = key;
        })
        .catchError((Object error) {
          debugPrint('Push registration unavailable: ${error.runtimeType}');
        })
        .whenComplete(() {
          _registering = false;
          if (_queuedRegistration) {
            _queuedRegistration = false;
            _registerIfReady();
          }
        });
  }

  void _handleMessage(RemoteMessage message) {
    if (message.data['kind'] == 'candidate_review' ||
        message.data['kind'] == 'budget_alert') {
      onReview();
    }
  }

  void dispose() {
    auth.removeListener(_sessionChanged);
    _tokenRefresh?.cancel();
    _opened?.cancel();
    _foreground?.cancel();
  }
}
