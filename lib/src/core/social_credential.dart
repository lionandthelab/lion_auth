import '../config/lion_auth_config.dart';

/// 소셜 프로바이더에서 획득한 자격 증명.
///
/// 어떤 백엔드로 세션을 만들지와 무관한, 순수한 "프로바이더 토큰 묶음"이다.
class SocialCredential {
  const SocialCredential({
    required this.provider,
    this.idToken,
    this.accessToken,
    this.authCode,
    this.redirectUri,
    this.state,
    this.rawNonce,
    this.email,
    this.displayName,
  });

  final LionAuthProviderId provider;

  /// OIDC id_token (google, kakao, apple).
  final String? idToken;

  /// 프로바이더 access_token (kakao, naver 네이티브).
  final String? accessToken;

  /// 인가 코드 (naver 웹 리다이렉트 플로우 — 서버 브로커가 교환).
  final String? authCode;

  /// [authCode] 교환 시 필요한 redirect_uri.
  final String? redirectUri;

  /// CSRF 방지용 state (인가 코드 플로우).
  final String? state;

  /// Apple 로그인의 nonce 원문 (id_token 검증용).
  final String? rawNonce;

  /// 프로바이더가 함께 알려준 프로필 힌트 (없을 수 있음).
  final String? email;
  final String? displayName;

  Map<String, dynamic> toMap() => {
        'provider': provider.name,
        if (idToken != null) 'id_token': idToken,
        if (accessToken != null) 'access_token': accessToken,
        if (authCode != null) 'auth_code': authCode,
        if (redirectUri != null) 'redirect_uri': redirectUri,
        if (state != null) 'state': state,
        if (email != null) 'email': email,
        if (displayName != null) 'display_name': displayName,
      };
}

/// 사용자가 로그인 창을 닫는 등 의도적으로 취소한 경우.
class SocialSignInCancelled implements Exception {
  const SocialSignInCancelled();
}

/// 자격 획득 실패 (설정 누락, SDK 오류 등). [message]는 사용자 노출용 한국어.
class SocialSignInException implements Exception {
  const SocialSignInException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'SocialSignInException: $message ($cause)';
}
