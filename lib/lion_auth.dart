/// 라이온앤더랩 공용 한국 특화 소셜 로그인 모듈.
///
/// 구조:
/// - core: 소셜 프로바이더 자격 획득 (백엔드 비종속)
/// - backend: 세션 발급 어댑터 (Supabase / 자체 HTTP 서버)
/// - state: ChangeNotifier 기반 컨트롤러
/// - ui: LionAuthScreen + 소셜 버튼
library lion_auth;

export 'src/config/lion_auth_config.dart';
export 'src/config/lion_auth_theme.dart';
export 'src/core/social_credential.dart';
export 'src/core/social_credential_provider.dart';
export 'src/core/providers/google_credential_provider.dart';
export 'src/core/providers/kakao_credential_provider.dart';
export 'src/core/providers/naver_credential_provider.dart';
export 'src/core/providers/apple_credential_provider.dart';
export 'src/backend/lion_auth_backend.dart';
export 'src/backend/supabase_auth_backend.dart';
export 'src/backend/http_auth_backend.dart';
export 'src/state/lion_auth_controller.dart';
export 'src/ui/lion_auth_screen.dart';
export 'src/ui/social_login_buttons.dart';
