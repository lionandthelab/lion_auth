import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lion_messaging_backend.dart';

/// 자체 서버(비-Supabase 서비스)를 저장/발송 백엔드로 쓰는 어댑터.
///
/// 서버 계약 (모든 응답은 JSON):
/// - POST {baseUrl}{registerPath}    body: PushTokenRegistration.toMap()
/// - POST {baseUrl}{unregisterPath}  body: {token}
/// - POST {baseUrl}{sendPath}        body: NotificationRequest.toMap()
///
/// send 성공 응답: {"accepted": bool, "message_id"?, "fallback_used"?}
/// 실패 응답: {"error": "사용자 노출용 한국어 메시지"}
///
/// 호출자 식별은 [accessTokenProvider]가 주는 Bearer 토큰으로 한다(로그인 이후).
class HttpLionMessagingBackend implements LionMessagingBackend {
  HttpLionMessagingBackend({
    required this.baseUrl,
    this.registerPath = '/messaging/register-token',
    this.unregisterPath = '/messaging/unregister-token',
    this.sendPath = '/messaging/send',
    this.defaultHeaders = const {},
    this.accessTokenProvider,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String registerPath;
  final String unregisterPath;
  final String sendPath;
  final Map<String, String> defaultHeaders;

  /// 요청마다 Authorization: Bearer <token> 을 붙일 토큰 공급자.
  final Future<String?> Function()? accessTokenProvider;

  final http.Client _http;

  @override
  Future<void> registerPushToken(PushTokenRegistration registration) async {
    await _post(registerPath, registration.toMap());
  }

  @override
  Future<void> unregisterPushToken(String token) async {
    await _post(unregisterPath, {'token': token});
  }

  @override
  Future<NotificationResult> requestSend(NotificationRequest request) async {
    final data = await _post(sendPath, request.toMap());
    return NotificationResult.fromMap(data);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final token = await accessTokenProvider?.call();
    final http.Response response;
    try {
      response = await _http.post(
        Uri.parse('$baseUrl$path'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
          ...defaultHeaders,
        },
        body: jsonEncode(body),
      );
    } catch (error) {
      throw LionMessagingException('서버에 연결하지 못했습니다.', error);
    }

    Map<String, dynamic> data = const {};
    if (response.body.isNotEmpty) {
      try {
        data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      } catch (_) {
        // JSON 이 아니면 아래 상태 코드 분기에서 처리.
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    final message = (data['error'] as String?) ??
        '요청에 실패했습니다. (HTTP ${response.statusCode})';
    throw LionMessagingException(message);
  }
}
