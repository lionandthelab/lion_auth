/// 발송 채널.
///
/// - [alimtalk]: 카카오 알림톡(승인 템플릿 필요).
/// - [sms]: SMS/LMS 직접 발송.
/// - [push]: FCM 푸시.
/// - [auto]: 알림톡 시도 후 실패 시 SMS/LMS 자동 대체(서버가 판단).
enum NotificationChannel { alimtalk, sms, push, auto }

extension NotificationChannelName on NotificationChannel {
  String get wireName => name; // alimtalk|sms|push|auto
}

/// 기기 푸시 토큰 등록 정보.
class PushTokenRegistration {
  const PushTokenRegistration({
    required this.token,
    required this.platform,
    this.deviceId,
    this.appVersion,
  });

  final String token;

  /// 'android' | 'ios' | 'web' (DB check 제약과 일치).
  final String platform;
  final String? deviceId;
  final String? appVersion;

  Map<String, dynamic> toMap() => {
        'token': token,
        'platform': platform,
        if (deviceId != null) 'device_id': deviceId,
        if (appVersion != null) 'app_version': appVersion,
      };
}

/// 발송 요청. 실제 수신자 토큰/전화번호 해석은 서버(service_role)에서 수행한다.
class NotificationRequest {
  const NotificationRequest({
    required this.channel,
    required this.toUserIds,
    this.templateId,
    this.variables = const {},
    this.title,
    this.body,
    this.data = const {},
  });

  final NotificationChannel channel;

  /// 수신 대상 사용자 ID 목록(서버가 토큰/전화번호로 해석).
  final List<String> toUserIds;

  /// 알림톡 템플릿 코드(alimtalk/auto).
  final String? templateId;

  /// 알림톡 `#{변수}` 치환값 / SMS 치환.
  final Map<String, String> variables;

  /// 푸시/SMS 본문.
  final String? title;
  final String? body;

  /// 푸시 data 페이로드(라우팅 등).
  final Map<String, String> data;

  Map<String, dynamic> toMap() => {
        'channel': channel.wireName,
        'to_user_ids': toUserIds,
        if (templateId != null) 'template_id': templateId,
        if (variables.isNotEmpty) 'variables': variables,
        if (title != null) 'title': title,
        if (body != null) 'body': body,
        if (data.isNotEmpty) 'data': data,
      };
}

/// 발송 요청 결과 요약(서버 응답).
class NotificationResult {
  const NotificationResult({
    required this.accepted,
    this.messageId,
    this.fallbackUsed,
    this.raw = const {},
  });

  final bool accepted;

  /// 프로바이더 메시지/그룹 식별자.
  final String? messageId;

  /// 알림톡 실패로 실제 대체된 채널(예: 'sms'). null 이면 대체 없음.
  final String? fallbackUsed;

  final Map<String, dynamic> raw;

  factory NotificationResult.fromMap(Map<String, dynamic> map) {
    return NotificationResult(
      accepted: map['accepted'] == true,
      messageId: map['message_id'] as String?,
      fallbackUsed: map['fallback_used'] as String?,
      raw: map,
    );
  }
}

/// 메시징 백엔드 처리 실패. [message]는 사용자 노출용 한국어 문구.
class LionMessagingException implements Exception {
  const LionMessagingException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'LionMessagingException: $message ($cause)';
}

/// 푸시 토큰 저장 + 발송 중개 추상화.
///
/// - Supabase 서비스: [SupabaseLionMessagingBackend]
/// - 자체 서버(GCloud VM 등): [HttpLionMessagingBackend]
///
/// 세션 발급([LionAuthBackend])과 병렬 구조 — 서로 독립적이다.
abstract class LionMessagingBackend {
  /// 기기 푸시 토큰 등록/갱신(로그인 사용자 기준).
  Future<void> registerPushToken(PushTokenRegistration registration);

  /// 기기 푸시 토큰 폐기(로그아웃).
  Future<void> unregisterPushToken(String token);

  /// 서버 인가 하에 알림톡/SMS/푸시 발송을 요청한다.
  Future<NotificationResult> requestSend(NotificationRequest request);
}
