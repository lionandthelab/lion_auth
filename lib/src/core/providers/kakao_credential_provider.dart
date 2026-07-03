import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import '../../config/lion_auth_config.dart';
import '../social_credential.dart';
import '../social_credential_provider.dart';

/// Kakao 자격 획득.
///
/// - 앱: 카카오톡 설치 시 앱투앱 로그인, 아니면 카카오계정 로그인.
/// - 웹: Kakao Flutter SDK의 웹 지원(카카오계정 팝업)을 그대로 사용.
///
/// Kakao Developers 콘솔에서 OpenID Connect를 활성화해야 id_token이 발급되며,
/// Supabase 백엔드는 id_token 경로를 사용한다.
class KakaoCredentialProvider extends SocialCredentialProvider {
  KakaoCredentialProvider(this.options);

  final KakaoAuthOptions options;
  bool _initialized = false;

  @override
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    KakaoSdk.init(
      nativeAppKey: options.nativeAppKey,
      javaScriptAppKey: options.javaScriptAppKey,
    );
  }

  @override
  Future<SocialCredential> acquire() async {
    await ensureInitialized();

    OAuthToken token;
    try {
      if (!kIsWeb && await isKakaoTalkInstalled()) {
        try {
          token = await UserApi.instance.loginWithKakaoTalk();
        } catch (error) {
          if (_isCancelled(error)) throw const SocialSignInCancelled();
          // 카카오톡은 있지만 로그인 불가(미로그인 등) → 계정 로그인 폴백.
          token = await UserApi.instance.loginWithKakaoAccount();
        }
      } else {
        token = await UserApi.instance.loginWithKakaoAccount();
      }
    } on SocialSignInCancelled {
      rethrow;
    } catch (error) {
      if (_isCancelled(error)) throw const SocialSignInCancelled();
      throw SocialSignInException('카카오 로그인에 실패했습니다.', error);
    }

    return SocialCredential(
      provider: LionAuthProviderId.kakao,
      idToken: token.idToken,
      accessToken: token.accessToken,
    );
  }

  bool _isCancelled(Object error) {
    if (error is PlatformException && error.code == 'CANCELED') return true;
    if (error is KakaoAuthException &&
        error.error == AuthErrorCause.accessDenied) {
      return true;
    }
    return false;
  }
}
