import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import '../../config/lion_auth_config.dart';
import '../social_credential.dart';
import '../social_credential_provider.dart';

/// Kakao 자격 획득.
///
/// 앱·웹 모두 공식 `loginWithKakaoAccount()`(Safari / Custom Tabs)를 쓴다.
/// 카카오톡 앱투앱은 쓰지 않는다. OpenID Connect가 켜져 있어야 id_token이 나온다.
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

    late final OAuthToken token;
    try {
      token = await UserApi.instance.loginWithKakaoAccount();
    } on SocialSignInCancelled {
      rethrow;
    } catch (error) {
      if (_isCancelled(error)) throw const SocialSignInCancelled();
      throw SocialSignInException('카카오 로그인에 실패했습니다.', error);
    }

    final idToken = token.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const SocialSignInException(
        '카카오 OpenID Connect가 꺼져 있어 ID 토큰을 받지 못했습니다.',
      );
    }

    return SocialCredential(
      provider: LionAuthProviderId.kakao,
      idToken: idToken,
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
