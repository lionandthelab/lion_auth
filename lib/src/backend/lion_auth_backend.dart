import '../config/lion_auth_config.dart';
import '../core/social_credential.dart';

/// 로그인 완료 후 백엔드가 돌려주는 세션 요약.
///
/// 백엔드별 원본 세션(Supabase Session, 자체 JWT 등)은 [raw]로 전달된다.
class LionAuthSession {
  const LionAuthSession({
    required this.userId,
    this.email = '',
    this.displayName = '',
    this.provider = '',
    this.isNewUser = false,
    this.metadata = const {},
    this.raw,
  });

  final String userId;
  final String email;
  final String displayName;

  /// 로그인에 사용된 프로바이더 (email, google, kakao, naver, apple).
  final String provider;

  /// 이번 로그인으로 계정이 새로 만들어졌는지 (백엔드가 판단 가능한 경우).
  final bool isNewUser;

  /// 백엔드 user metadata (프로필 보완 판단 등에 사용).
  final Map<String, dynamic> metadata;

  final Object? raw;
}

/// 백엔드 처리 실패. [message]는 사용자 노출용 한국어 문구.
class LionAuthBackendException implements Exception {
  const LionAuthBackendException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'LionAuthBackendException: $message ($cause)';
}

/// 세션 발급자 추상화.
///
/// - Supabase 서비스: [SupabaseLionAuthBackend]
/// - 자체 서버(GCloud VM 등): [HttpLionAuthBackend]
abstract class LionAuthBackend {
  /// 소셜 자격 증명으로 로그인(필요 시 가입)하고 세션을 발급한다.
  Future<LionAuthSession> signInWithCredential(SocialCredential credential);

  Future<LionAuthSession> signInWithPassword({
    required String email,
    required String password,
  });

  /// [metadata]에는 extraSignUpFields 값이 key-value로 담긴다.
  Future<LionAuthSession> signUpWithPassword({
    required String email,
    required String password,
    Map<String, dynamic> metadata = const {},
  });

  Future<void> sendPasswordReset(String email);

  /// 공급자 OAuth 리다이렉트 로그인 시작(웹 커스텀 버튼용). 페이지가 공급자로
  /// 떠났다가 돌아오면 세션 발급자(예: Supabase)가 콜백을 처리한다.
  Future<void> signInWithOAuthRedirect(
    LionAuthProviderId provider, {
    String? redirectTo,
  });

  Future<void> signOut();
}
