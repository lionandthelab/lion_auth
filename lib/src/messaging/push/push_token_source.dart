import 'push_token_source_stub.dart'
    if (dart.library.io) 'push_token_source_firebase.dart'
    if (dart.library.html) 'push_token_source_firebase.dart';

/// 기기 플랫폼 구분.
enum PushPlatform { android, ios, web, unsupported }

extension PushPlatformName on PushPlatform {
  /// DB `push_tokens.platform` 에 저장되는 값. unsupported 는 등록 불가.
  String get wireName => switch (this) {
        PushPlatform.android => 'android',
        PushPlatform.ios => 'ios',
        PushPlatform.web => 'web',
        PushPlatform.unsupported => 'unsupported',
      };
}

/// 수신한 푸시 메시지의 정규화 표현(프로바이더 SDK 타입에 비종속).
class PushMessage {
  const PushMessage({
    this.title,
    this.body,
    this.data = const {},
  });

  final String? title;
  final String? body;
  final Map<String, String> data;
}

/// 푸시 토큰 획득/수신 전략. 플랫폼 차이(웹 VAPID, iOS APNs 등)를 내부에서 흡수한다.
///
/// 구현체는 [createPushTokenSource]로 생성한다(웹/네이티브는 firebase_messaging,
/// 미지원 플랫폼은 스텁). 세션 발급([LionAuthBackend])과 무관하다.
abstract class PushTokenSource {
  PushPlatform get platform;

  /// 이 플랫폼에서 푸시가 지원되는지(미지원이면 토큰 등록을 건너뛴다).
  bool get isSupported => platform != PushPlatform.unsupported;

  /// SDK 초기화 등 선행 작업. 컨트롤러 initialize 시 1회 호출.
  Future<void> ensureInitialized() async {}

  /// 알림 권한을 요청하고 최종 허용 여부를 반환.
  Future<bool> requestPermission();

  /// 현재 기기 토큰을 발급/반환. 실패하거나 미지원이면 null.
  /// 웹은 [vapidKey]가 필요하다.
  Future<String?> getToken({String? vapidKey});

  /// 토큰 갱신 스트림(FCM 이 주기적으로 토큰을 재발급).
  Stream<String> get onTokenRefresh;

  /// 현재 토큰을 폐기(로그아웃 시).
  Future<void> deleteToken();

  /// 포그라운드 수신 메시지 스트림(정규화).
  Stream<PushMessage> get onForegroundMessage;
}

/// 현재 플랫폼에 맞는 [PushTokenSource] 생성.
PushTokenSource createPushTokenSource() => makePushTokenSource();
