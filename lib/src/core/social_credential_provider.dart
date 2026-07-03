import 'social_credential.dart';

/// 소셜 프로바이더별 자격 획득 전략.
///
/// 구현체는 웹/앱 플랫폼 차이를 내부에서 흡수하고, 결과를
/// [SocialCredential]로 통일해 돌려준다. 백엔드(세션 발급)와는 무관하다.
abstract class SocialCredentialProvider {
  /// 현재 플랫폼에서 인터랙티브 획득([acquire])이 가능한지.
  /// (예: 웹 Google은 GIS 버튼 이벤트로만 획득 → false)
  bool get canAcquireInteractively => true;

  /// SDK 초기화 등 선행 작업. 컨트롤러 initialize 시 1회 호출된다.
  Future<void> ensureInitialized() async {}

  /// 버튼 탭으로 시작하는 인터랙티브 자격 획득.
  ///
  /// 사용자가 취소하면 [SocialSignInCancelled]를 던진다.
  /// 웹 리다이렉트 플로우처럼 페이지를 떠나는 경우 이 Future는 완료되지 않는다.
  Future<SocialCredential> acquire();

  /// 리다이렉트 복귀 등 앱 시작 시점에 회수할 자격이 있으면 반환.
  Future<SocialCredential?> resumePendingCredential() async => null;
}
