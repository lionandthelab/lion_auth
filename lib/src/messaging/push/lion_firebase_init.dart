import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase 초기화 헬퍼.
///
/// 호스트 앱이 `firebase_core` 를 직접 import 하지 않고도 초기화할 수 있게 한다.
/// (프론트엔드가 firebase_core 를 직접 의존하지 않도록 — 시크릿/설정을 이 모듈로 집약)
///
/// - 네이티브: [options] 없이 호출하면 google-services.json / GoogleService-Info.plist
///   에서 자동 로드한다. 파일이 없으면 실패하고 false 를 반환한다(푸시 비활성).
/// - 웹: [webOptions] 가 반드시 필요하다(없으면 false). Firebase 콘솔의 웹 앱
///   설정값을 map 으로 넘긴다.
///
/// 성공하면 true, 미설정/실패면 false 를 반환한다(앱이 죽지 않고 푸시만 비활성화).
Future<bool> initLionFirebase({Map<String, String>? webOptions}) async {
  try {
    if (Firebase.apps.isNotEmpty) return true;
    if (kIsWeb) {
      if (webOptions == null || (webOptions['apiKey'] ?? '').isEmpty) {
        return false; // 웹은 옵션 필수 — 미설정 시 조용히 비활성.
      }
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: webOptions['apiKey'] ?? '',
          appId: webOptions['appId'] ?? '',
          messagingSenderId: webOptions['messagingSenderId'] ?? '',
          projectId: webOptions['projectId'] ?? '',
          authDomain: webOptions['authDomain'],
          storageBucket: webOptions['storageBucket'],
        ),
      );
    } else {
      await Firebase.initializeApp();
    }
    return true;
  } catch (error) {
    debugPrint('[LionPush] Firebase 초기화 실패(푸시 비활성): $error');
    return false;
  }
}
