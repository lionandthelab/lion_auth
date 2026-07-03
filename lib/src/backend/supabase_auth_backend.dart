import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/lion_auth_config.dart';
import '../core/social_credential.dart';
import 'lion_auth_backend.dart';

/// Supabase Auth를 세션 발급자로 쓰는 백엔드.
///
/// - google / kakao / apple: `signInWithIdToken` (네이티브 id_token 그랜트)
/// - naver: Supabase 미지원 프로바이더 → Edge Function [brokerFunctionName]이
///   토큰 검증/코드 교환 후 magiclink token_hash를 발급하고, 클라이언트가
///   `verifyOTP`로 정식 세션을 만든다.
class SupabaseLionAuthBackend implements LionAuthBackend {
  SupabaseLionAuthBackend(
    this.client, {
    this.brokerFunctionName = 'social-broker',
    this.emailRedirectUrl,
  });

  final SupabaseClient client;

  /// Naver 등 미지원 프로바이더를 중개하는 Edge Function 이름.
  final String brokerFunctionName;

  /// 회원가입 확인 메일의 리다이렉트 URL.
  final String? emailRedirectUrl;

  @override
  Future<LionAuthSession> signInWithCredential(
    SocialCredential credential,
  ) async {
    try {
      switch (credential.provider) {
        case LionAuthProviderId.google:
          return _toSession(
            await client.auth.signInWithIdToken(
              provider: OAuthProvider.google,
              idToken: _requireIdToken(credential),
              accessToken: credential.accessToken,
            ),
            credential.provider.name,
          );
        case LionAuthProviderId.kakao:
          if (credential.idToken == null || credential.idToken!.isEmpty) {
            throw const LionAuthBackendException(
              '카카오 ID 토큰이 없습니다. Kakao Developers 콘솔에서 '
              'OpenID Connect를 활성화해 주세요.',
            );
          }
          return _toSession(
            await client.auth.signInWithIdToken(
              provider: OAuthProvider.kakao,
              idToken: credential.idToken!,
              accessToken: credential.accessToken,
            ),
            credential.provider.name,
          );
        case LionAuthProviderId.apple:
          return _toSession(
            await client.auth.signInWithIdToken(
              provider: OAuthProvider.apple,
              idToken: _requireIdToken(credential),
              nonce: credential.rawNonce,
            ),
            credential.provider.name,
          );
        case LionAuthProviderId.naver:
          return _signInViaBroker(credential);
      }
    } on LionAuthBackendException {
      rethrow;
    } on AuthException catch (e) {
      throw LionAuthBackendException(_koreanAuthMessage(e), e);
    }
  }

  /// Edge Function 브로커를 거쳐 magiclink token_hash → 세션 발급.
  Future<LionAuthSession> _signInViaBroker(SocialCredential credential) async {
    final Map<String, dynamic> data;
    try {
      final response = await client.functions.invoke(
        brokerFunctionName,
        body: credential.toMap(),
      );
      data = Map<String, dynamic>.from(response.data as Map);
    } on FunctionException catch (e) {
      final detail = e.details;
      final message = detail is Map && detail['error'] is String
          ? detail['error'] as String
          : '소셜 로그인 처리 중 서버 오류가 발생했습니다.';
      throw LionAuthBackendException(message, e);
    }

    final tokenHash = data['token_hash'] as String?;
    if (tokenHash == null || tokenHash.isEmpty) {
      throw const LionAuthBackendException('서버에서 로그인 토큰을 받지 못했습니다.');
    }

    try {
      final response = await client.auth.verifyOTP(
        type: OtpType.magiclink,
        tokenHash: tokenHash,
      );
      return _toSession(
        response,
        credential.provider.name,
        isNewUser: data['is_new_user'] == true,
      );
    } on AuthException catch (e) {
      throw LionAuthBackendException(_koreanAuthMessage(e), e);
    }
  }

  @override
  Future<LionAuthSession> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return _toSession(response, 'email');
    } on AuthException catch (e) {
      throw LionAuthBackendException(_koreanAuthMessage(e), e);
    }
  }

  @override
  Future<LionAuthSession> signUpWithPassword({
    required String email,
    required String password,
    Map<String, dynamic> metadata = const {},
  }) async {
    try {
      final response = await client.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: emailRedirectUrl,
        data: metadata.isEmpty ? null : metadata,
      );
      if (response.user == null) {
        throw const LionAuthBackendException('회원가입 계정을 생성하지 못했습니다.');
      }
      return _toSession(response, 'email', isNewUser: true);
    } on AuthException catch (e) {
      throw LionAuthBackendException(_koreanAuthMessage(e), e);
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await client.auth.resetPasswordForEmail(
        email,
        redirectTo: emailRedirectUrl,
      );
    } on AuthException catch (e) {
      throw LionAuthBackendException(_koreanAuthMessage(e), e);
    }
  }

  @override
  Future<void> signOut() => client.auth.signOut();

  String _requireIdToken(SocialCredential credential) {
    final idToken = credential.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw LionAuthBackendException(
        '${credential.provider.name} ID 토큰이 없습니다. 클라이언트 설정을 확인해 주세요.',
      );
    }
    return idToken;
  }

  LionAuthSession _toSession(
    AuthResponse response,
    String provider, {
    bool isNewUser = false,
  }) {
    final user = response.user;
    if (user == null) {
      throw const LionAuthBackendException('로그인 세션을 생성하지 못했습니다.');
    }
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    return LionAuthSession(
      userId: user.id,
      email: user.email ?? '',
      displayName: (metadata['full_name'] as String?) ??
          (metadata['name'] as String?) ??
          '',
      provider: provider,
      isNewUser: isNewUser,
      metadata: metadata,
      raw: response.session,
    );
  }

  String _koreanAuthMessage(AuthException e) {
    final code = e.code ?? '';
    final message = e.message;
    if (code == 'invalid_credentials' ||
        message.contains('Invalid login credentials')) {
      return '이메일 또는 비밀번호가 올바르지 않습니다.';
    }
    if (code == 'email_not_confirmed') {
      return '이메일 인증이 완료되지 않았습니다. 받은편지함을 확인해 주세요.';
    }
    if (code == 'user_already_exists' || message.contains('already registered')) {
      return '이미 가입된 이메일입니다. 로그인해 주세요.';
    }
    if (code == 'over_request_rate_limit') {
      return '요청이 너무 잦습니다. 잠시 후 다시 시도해 주세요.';
    }
    if (code == 'provider_disabled' || message.contains('provider is not enabled')) {
      return '이 로그인 방식이 서버에 아직 활성화되지 않았습니다. (설정 필요: $message)';
    }
    return '로그인에 실패했습니다. ($message)';
  }
}
