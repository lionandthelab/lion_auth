import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// FCM 백그라운드 메시지 핸들러.
///
/// FCM 은 백그라운드 핸들러가 **최상위(top-level) 또는 static 함수**일 것을
/// 강제하며, `@pragma('vm:entry-point')` 로 tree-shaking 을 막아야 한다.
/// 이 제약 때문에 컨트롤러 클래스 안에 둘 수 없어 별도 파일로 격리한다.
///
/// 기본 구현은 Firebase 를 초기화만 한다(데이터 메시지 백그라운드 수신 활성화).
/// 서비스가 백그라운드에서 추가 처리(로컬 알림 표시 등)를 원하면 자체 top-level
/// 함수를 만들어 [registerLionPushBackgroundHandler]에 넘긴다.
@pragma('vm:entry-point')
Future<void> lionPushBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // UI 갱신 금지 — 필요 시 로컬 저장/HTTP 만 수행.
}

/// 앱 `main()` 에서 `runApp` 전에 1회 호출해 백그라운드 핸들러를 등록한다.
///
/// 웹은 `firebase-messaging-sw.js` 서비스워커가 백그라운드를 담당하므로 no-op.
void registerLionPushBackgroundHandler([
  Future<void> Function(RemoteMessage message)? handler,
]) {
  if (kIsWeb) return;
  FirebaseMessaging.onBackgroundMessage(handler ?? lionPushBackgroundHandler);
}
