import 'package:supabase_flutter/supabase_flutter.dart';

import 'lion_messaging_backend.dart';

/// Supabase 를 저장/발송 백엔드로 쓰는 어댑터.
///
/// - 토큰 등록/폐기: `push_tokens` 테이블에 **RLS 보호 직접 write**(본인 행만).
///   Edge Function 왕복이 불필요하므로 단순하다.
/// - 발송: `lion-notify` Edge Function 을 호출한다(시크릿은 서버에만 존재).
class SupabaseLionMessagingBackend implements LionMessagingBackend {
  SupabaseLionMessagingBackend(
    this.client, {
    this.notifyFunctionName = 'lion-notify',
    this.pushTokensTable = 'push_tokens',
  });

  final SupabaseClient client;
  final String notifyFunctionName;
  final String pushTokensTable;

  String get _requireUserId {
    final userId = client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      throw const LionMessagingException('로그인 후에 알림을 설정할 수 있습니다.');
    }
    return userId;
  }

  @override
  Future<void> registerPushToken(PushTokenRegistration registration) async {
    final userId = _requireUserId;
    try {
      await client.from(pushTokensTable).upsert(
        {
          'user_id': userId,
          ...registration.toMap(),
          'revoked_at': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,token',
      );
    } on PostgrestException catch (e) {
      throw LionMessagingException('푸시 토큰 등록에 실패했습니다.', e);
    }
  }

  @override
  Future<void> unregisterPushToken(String token) async {
    final userId = _requireUserId;
    try {
      await client
          .from(pushTokensTable)
          .update({'revoked_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', userId)
          .eq('token', token);
    } on PostgrestException catch (e) {
      throw LionMessagingException('푸시 토큰 해제에 실패했습니다.', e);
    }
  }

  @override
  Future<NotificationResult> requestSend(NotificationRequest request) async {
    try {
      final response = await client.functions.invoke(
        notifyFunctionName,
        body: request.toMap(),
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      return NotificationResult.fromMap(data);
    } on FunctionException catch (e) {
      final detail = e.details;
      final message = detail is Map && detail['error'] is String
          ? detail['error'] as String
          : '알림 발송 중 서버 오류가 발생했습니다.';
      throw LionMessagingException(message, e);
    } catch (e) {
      throw LionMessagingException('알림 발송 요청에 실패했습니다.', e);
    }
  }
}
