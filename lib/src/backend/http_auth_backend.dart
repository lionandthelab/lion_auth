import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/lion_auth_config.dart';
import '../core/social_credential.dart';
import 'lion_auth_backend.dart';

/// 자체 서버(GCloud VM 등 비-Supabase 서비스)를 세션 발급자로 쓰는 백엔드.
///
/// 서버 계약 (모든 응답은 JSON):
/// - POST {baseUrl}{socialPath}    body: SocialCredential.toMap()
/// - POST {baseUrl}{signInPath}    body: {email, password}
/// - POST {baseUrl}{signUpPath}    body: {email, password, metadata}
/// - POST {baseUrl}{resetPath}     body: {email}
///
/// 성공 응답: {"user": {"id", "email", "display_name", "metadata"},
///            "is_new_user": bool, ...토큰 필드는 서비스 자유}
/// 실패 응답: {"error": "사용자 노출용 한국어 메시지"}
///
/// 토큰 보관(예: secure storage)은 [onSession] 콜백에서 서비스가 처리한다.
class HttpLionAuthBackend implements LionAuthBackend {
  HttpLionAuthBackend({
    required this.baseUrl,
    this.socialPath = '/auth/social',
    this.signInPath = '/auth/sign-in',
    this.signUpPath = '/auth/sign-up',
    this.resetPath = '/auth/password-reset',
    this.signOutPath = '/auth/sign-out',
    this.defaultHeaders = const {},
    this.onSession,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String socialPath;
  final String signInPath;
  final String signUpPath;
  final String resetPath;
  final String signOutPath;
  final Map<String, String> defaultHeaders;

  /// 세션 발급 직후 호출 — 서비스가 토큰 저장 등을 수행.
  final void Function(Map<String, dynamic> rawBody)? onSession;

  final http.Client _http;

  @override
  Future<LionAuthSession> signInWithCredential(
    SocialCredential credential,
  ) =>
      _postForSession(socialPath, credential.toMap(),
          provider: credential.provider.name);

  @override
  Future<LionAuthSession> signInWithPassword({
    required String email,
    required String password,
  }) =>
      _postForSession(
        signInPath,
        {'email': email, 'password': password},
        provider: 'email',
      );

  @override
  Future<LionAuthSession> signUpWithPassword({
    required String email,
    required String password,
    Map<String, dynamic> metadata = const {},
  }) =>
      _postForSession(
        signUpPath,
        {'email': email, 'password': password, 'metadata': metadata},
        provider: 'email',
      );

  @override
  Future<void> sendPasswordReset(String email) async {
    await _post(resetPath, {'email': email});
  }

  @override
  Future<void> signInWithOAuthRedirect(
    LionAuthProviderId provider, {
    String? redirectTo,
  }) async {
    throw const LionAuthBackendException(
      '이 백엔드는 OAuth 리다이렉트를 지원하지 않습니다.',
    );
  }

  @override
  Future<void> signOut() async {
    try {
      await _post(signOutPath, const {});
    } on LionAuthBackendException {
      // 서버 측 세션 정리는 실패해도 클라이언트 로그아웃을 막지 않는다.
    }
  }

  Future<LionAuthSession> _postForSession(
    String path,
    Map<String, dynamic> body, {
    required String provider,
  }) async {
    final data = await _post(path, body);
    final user = Map<String, dynamic>.from(
      (data['user'] as Map?) ?? const {},
    );
    final userId = (user['id'] ?? '').toString();
    if (userId.isEmpty) {
      throw const LionAuthBackendException('서버 응답에 사용자 정보가 없습니다.');
    }
    onSession?.call(data);
    return LionAuthSession(
      userId: userId,
      email: (user['email'] as String?) ?? '',
      displayName: (user['display_name'] as String?) ?? '',
      provider: provider,
      isNewUser: data['is_new_user'] == true,
      metadata: Map<String, dynamic>.from(
        (user['metadata'] as Map?) ?? const {},
      ),
      raw: data,
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final http.Response response;
    try {
      response = await _http.post(
        Uri.parse('$baseUrl$path'),
        headers: {
          'Content-Type': 'application/json',
          ...defaultHeaders,
        },
        body: jsonEncode(body),
      );
    } catch (error) {
      throw LionAuthBackendException('서버에 연결하지 못했습니다.', error);
    }

    Map<String, dynamic> data = const {};
    if (response.body.isNotEmpty) {
      try {
        data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      } catch (_) {
        // JSON이 아니면 아래 상태 코드 분기에서 처리.
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    final message = (data['error'] as String?) ??
        '요청에 실패했습니다. (HTTP ${response.statusCode})';
    throw LionAuthBackendException(message);
  }
}
