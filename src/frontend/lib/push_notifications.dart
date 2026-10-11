import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'api/auth_repository.dart';

class PushNotifications with WidgetsBindingObserver {
  PushNotifications(
    this.auth, {
    required this.onReview,
    required this.onForeground,
    this.onLocation,
    this.onList,
  }) {
    auth.addListener(_sessionChanged);
    WidgetsBinding.instance.addObserver(this);
    _tokenRefresh = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _token = token;
      _tokenRetry?.cancel();
      _registeredFor = null;
      _registerIfReady();
    });
    _opened = FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
    _foreground = FirebaseMessaging.onMessage.listen(onForeground);
    _sessionChanged();
  }

  final AuthRepository auth;
  final void Function() onReview;
  final void Function()? onLocation;
  final void Function(String? listId)? onList;
  final void Function(RemoteMessage) onForeground;
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<RemoteMessage>? _opened;
  StreamSubscription<RemoteMessage>? _foreground;
  Timer? _tokenRetry;
  String? _token;
  String? _registeredFor;
  bool _registering = false;
  bool _queuedRegistration = false;
  bool _started = false;
  bool _loadingToken = false;
  bool _disposed = false;
  int _tokenAttempts = 0;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _disposed) return;
    if (_token == null) {
      _tokenAttempts = 0;
      _loadToken();
    } else {
      _registerIfReady();
    }
  }

  void _sessionChanged() {
    if (auth.session?.household == null) {
      _tokenRetry?.cancel();
      _registeredFor = null;
      return;
    }
    if (!_started) {
      _started = true;
      _start();
    } else if (_token == null) {
      _loadToken();
    } else {
      _registerIfReady();
    }
  }

  Future<void> _start() async {
    try {
      await FirebaseMessaging.instance.requestPermission();
      await _loadToken();
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _handleMessage(initial);
    } catch (error) {
      debugPrint('Push setup unavailable: ${error.runtimeType}');
    }
  }

  Future<void> _loadToken() async {
    if (_disposed || _loadingToken || auth.session?.household == null) return;
    _loadingToken = true;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS &&
          await FirebaseMessaging.instance.getAPNSToken() == null) {
        _scheduleTokenRetry();
        return;
      }
      _tokenRetry?.cancel();
      _token = await FirebaseMessaging.instance.getToken();
      _tokenAttempts = 0;
      _registerIfReady();
    } catch (error) {
      debugPrint('Push token unavailable: ${error.runtimeType}');
      _scheduleTokenRetry();
    } finally {
      _loadingToken = false;
    }
  }

  void _scheduleTokenRetry() {
    if (_disposed || auth.session?.household == null) return;
    if (_tokenAttempts++ >= 15) {
      debugPrint('Push token unavailable; retrying when the app resumes.');
      return;
    }
    _tokenRetry?.cancel();
    _tokenRetry = Timer(const Duration(seconds: 2), _loadToken);
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
    if (message.data['kind'] == 'list_items') {
      onList?.call(message.data['list_id'] as String?);
      return;
    }
    if (message.data['kind'] == 'location_started' ||
        message.data['kind'] == 'location_arrival') {
      onLocation?.call();
      return;
    }
    if (message.data['kind'] == 'candidate_review' ||
        message.data['kind'] == 'budget_alert') {
      onReview();
    }
  }

  void dispose() {
    _disposed = true;
    auth.removeListener(_sessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _tokenRetry?.cancel();
    _tokenRefresh?.cancel();
    _opened?.cancel();
    _foreground?.cancel();
  }
}
