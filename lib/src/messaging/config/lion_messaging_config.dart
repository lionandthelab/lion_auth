/// 알림톡(Solapi)의 클라이언트가 알아도 되는 비(非)시크릿 참조값.
///
/// **주의:** Solapi API Key/Secret 은 절대 여기 두지 않는다 — 발송은 서버
/// (lion-notify Edge Function)에서만 이뤄지고, 시크릿은 서버 시크릿으로만
/// 보관한다. 여기의 값들은 UI 표시나 기본 템플릿 지정 등 편의용일 뿐이다.
class SolapiOptions {
  const SolapiOptions({
    this.pfId,
    this.senderNumber,
    this.defaultTemplateId,
  });

  /// 카카오 발신프로필 ID(PF...). 서버가 시크릿으로도 갖지만, 표시/검증용 참조.
  final String? pfId;

  /// 등록된 발신번호(표시용).
  final String? senderNumber;

  /// 별도 지정이 없을 때 사용할 기본 알림톡 템플릿 코드.
  final String? defaultTemplateId;
}

/// FCM(푸시) 클라이언트 설정.
class FcmOptions {
  const FcmOptions({
    this.vapidKey,
    this.autoRegisterOnSignIn = true,
    this.requestPermissionOnRegister = true,
  });

  /// 웹 푸시 공개키(VAPID). **공개키이므로 클라이언트 주입 안전.**
  /// 웹이 아닌 플랫폼에서는 무시된다. 웹에서 null 이면 토큰 발급이 실패한다.
  final String? vapidKey;

  /// 로그인 직후 자동으로 권한 요청 + 토큰 등록을 수행할지.
  final bool autoRegisterOnSignIn;

  /// 토큰 등록 시 알림 권한을 자동 요청할지. false 면 호스트가 별도로 요청.
  final bool requestPermissionOnRegister;
}

/// LionAuth 메시징 서브모듈의 서비스별 설정. 새 서비스는 이 객체만 채워 주입한다.
///
/// 로그인 설정([LionAuthConfig])과 병렬 구조 — 서로 독립적으로 주입/구성된다.
class LionMessagingConfig {
  const LionMessagingConfig({
    this.solapi,
    this.fcm,
    this.enablePush = true,
    this.enableAlimtalk = true,
    this.notifyFunctionName = 'lion-notify',
    this.pushTokensTable = 'push_tokens',
  });

  final SolapiOptions? solapi;
  final FcmOptions? fcm;

  /// 푸시 기능 사용 여부(토큰 등록/수신).
  final bool enablePush;

  /// 알림톡/SMS 발송 기능 사용 여부.
  final bool enableAlimtalk;

  /// 발송 중개 Edge Function 이름(서비스가 다른 이름으로 배포했을 때 대비).
  final String notifyFunctionName;

  /// 푸시 토큰을 저장하는 테이블 이름.
  final String pushTokensTable;
}
