import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_naver_login/flutter_naver_login.dart';
import 'package:flutter_naver_login/interface/types/naver_login_result.dart';
import 'package:flutter_naver_login/interface/types/naver_login_status.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/lion_auth_config.dart';
import '../social_credential.dart';
import '../social_credential_provider.dart';

/// Naver 자격 획득.
///
/// Naver는 OIDC 미지원이라 두 경로를 쓴다:
/// - 앱: 네이버 네이티브 SDK → access_token 획득.
///   (SDK 설정은 AndroidManifest.xml / Info.plist에 setup 스크립트가 주입)
/// - 웹: 인가 코드 리다이렉트 플로우. 페이지가 nid.naver.com으로 떠났다가
///   돌아오면 [resumePendingCredential]이 code를 회수한다.
///
/// 두 경우 모두 최종 세션 발급(토큰 검증/코드 교환)은 서버 브로커
/// (Supabase Edge Function `social-broker` 등)가 수행한다.
class NaverCredentialProvider extends SocialCredentialProvider {
  NaverCredentialProvider(this.options);

  static const _stateKey = 'lion_auth.naver.state';

  final NaverAuthOptions options;

  @override
  bool get hasPendingWebRedirect {
    if (!kIsWeb) return false;
    final params = Uri.base.queryParameters;
    final code = params['code'];
    final state = params['state'];
    return code != null && code.isNotEmpty && state != null && state.isNotEmpty;
  }

  @override
  Future<SocialCredential> acquire() async {
    if (kIsWeb) return _acquireWeb();
    return _acquireNative();
  }

  Future<SocialCredential> _acquireNative() async {
    final NaverLoginResult result;
    try {
      result = await FlutterNaverLogin.logIn();
    } catch (error) {
      throw SocialSignInException('네이버 로그인에 실패했습니다.', error);
    }

    if (result.status != NaverLoginStatus.loggedIn) {
      final message = result.errorMessage ?? '';
      if (message.toLowerCase().contains('cancel') ||
          message.contains('취소')) {
        throw const SocialSignInCancelled();
      }
      if (result.status == NaverLoginStatus.loggedOut) {
        throw const SocialSignInCancelled();
      }
      throw SocialSignInException('네이버 로그인에 실패했습니다. ($message)');
    }

    final token =
        result.accessToken ?? await FlutterNaverLogin.getCurrentAccessToken();
    if (token.accessToken.isEmpty) {
      throw const SocialSignInException('네이버 토큰을 받지 못했습니다.');
    }

    return SocialCredential(
      provider: LionAuthProviderId.naver,
      accessToken: token.accessToken,
      email: result.account?.email,
      displayName: result.account?.name,
    );
  }

  /// 웹: 현재 탭을 네이버 인가 페이지로 보낸다. (이 Future는 완료되지 않음)
  Future<SocialCredential> _acquireWeb() async {
    final state = _randomState();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stateKey, state);

    final redirectUri = _webRedirectUri();
    final authorizeUri = Uri.https('nid.naver.com', '/oauth2.0/authorize', {
      'response_type': 'code',
      'client_id': options.clientId,
      'redirect_uri': redirectUri,
      'state': state,
    });

    await launchUrl(authorizeUri, webOnlyWindowName: '_self');
    // 전체 페이지 리다이렉트 — 복귀 후 resumePendingCredential()이 이어받는다.
    return Completer<SocialCredential>().future;
  }

  @override
  Future<SocialCredential?> resumePendingCredential() async {
    if (!kIsWeb) return null;

    final params = Uri.base.queryParameters;
    final code = params['code'];
    final state = params['state'];
    if (code == null || code.isEmpty || state == null) return null;

    final prefs = await SharedPreferences.getInstance();
    final expectedState = prefs.getString(_stateKey);
    if (expectedState == null) return null;
    await prefs.remove(_stateKey);
    if (expectedState != state) {
      throw const SocialSignInException(
        '네이버 로그인 상태 검증에 실패했습니다. 다시 시도해 주세요.',
      );
    }

    return SocialCredential(
      provider: LionAuthProviderId.naver,
      authCode: code,
      state: state,
      redirectUri: _webRedirectUri(),
    );
  }

  String _webRedirectUri() {
    if (options.webRedirectUri != null && options.webRedirectUri!.isNotEmpty) {
      return options.webRedirectUri!;
    }
    // 현재 페이지에서 쿼리/프래그먼트를 제거한 URL.
    final base = Uri.base;
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: base.path,
    ).toString();
  }

  String _randomState([int length = 24]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }
}
