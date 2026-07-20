import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_token_source.dart';

/// firebase_messaging 기반 구현. 웹 / Android / iOS 를 하나의 API 로 처리한다.
///
/// Firebase 초기화(`Firebase.initializeApp`)는 호스트 앱의 몫이다
/// (main_auth_lab.dart 가 `Supabase.initialize()` 를 호스트에서 부르는 것과 동일).
class FirebasePushTokenSource implements PushTokenSource {
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  PushPlatform get platform {
    if (kIsWeb) return PushPlatform.web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return PushPlatform.android;
      case TargetPlatform.iOS:
        return PushPlatform.ios;
      default:
        return PushPlatform.unsupported;
    }
  }

  @override
  bool get isSupported => platform != PushPlatform.unsupported;

  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final status = settings.authorizationStatus;
    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken({String? vapidKey}) async {
    if (!isSupported) return null;
    // iOS 는 APNs 토큰이 준비된 뒤에야 FCM 토큰이 발급된다.
    if (platform == PushPlatform.ios) {
      final apns = await _messaging.getAPNSToken();
      if (apns == null) {
        // APNs 미설정(시뮬레이터/키 누락) — 토큰 발급 불가.
        return null;
      }
    }
    return _messaging.getToken(vapidKey: kIsWeb ? vapidKey : null);
  }

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Future<void> deleteToken() => _messaging.deleteToken();

  @override
  Stream<PushMessage> get onForegroundMessage =>
      FirebaseMessaging.onMessage.map(_toPushMessage);

  PushMessage _toPushMessage(RemoteMessage message) => PushMessage(
        title: message.notification?.title,
        body: message.notification?.body,
        data: message.data.map(
          (key, value) => MapEntry(key, '$value'),
        ),
      );
}

PushTokenSource makePushTokenSource() => FirebasePushTokenSource();
