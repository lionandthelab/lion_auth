import 'package:flutter/foundation.dart';

/// 지원하는 소셜 프로바이더 식별자.
enum LionAuthProviderId { google, kakao, naver, apple }

/// Google 자격 획득 설정.
///
/// - [webClientId]: GCP 콘솔의 "웹 애플리케이션" OAuth 클라이언트 ID.
///   웹 빌드의 clientId이자, Android/iOS의 serverClientId(= id_token audience).
/// - [iosClientId]: GCP 콘솔의 "iOS" OAuth 클라이언트 ID.
class GoogleAuthOptions {
  const GoogleAuthOptions({
    required this.webClientId,
    this.iosClientId,
    this.webUseRenderedButton = false,
  });

  final String webClientId;
  final String? iosClientId;

  /// 웹에서 GIS 공식 렌더 버튼(FedCM id_token)을 쓸지 여부.
  /// false(기본)면 커스텀 원형 버튼 + Supabase OAuth 리다이렉트를 사용한다.
  final bool webUseRenderedButton;

  /// 실제 로그인이 가능한 설정인지 — webClientId가 비어 있지 않아야 한다.
  /// 콘솔 키 발급 전(빈 문자열/미설정)에는 버튼을 노출하지 않기 위한 게이트.
  bool get isUsable => webClientId.trim().isNotEmpty;
}

/// Kakao 자격 획득 설정. (Kakao Developers > 앱 키)
///
/// 카카오 로그인 + OpenID Connect 활성화가 선행되어야 id_token이 발급된다.
/// 카카오 세션을 발급받는 경로.
///
/// 어느 쪽을 고를지는 **Supabase 콘솔에 넣은 Client ID가 무엇인가**로 갈린다.
///
/// - [idToken]: 카카오 SDK가 받아 온 id_token을 그대로 `signInWithIdToken`에
///   넘긴다. Supabase는 id_token의 `aud`가 `external_kakao_client_id`와 같아야
///   통과시키는데, SDK가 인가를 요청할 때 쓰는 키는 **플랫폼마다 다르다**
///   (`KakaoSdk.appKey => kIsWeb ? javaScriptAppKey : nativeAppKey`).
///   따라서 이 경로는 콘솔 Client ID를 **그 플랫폼의 앱 키**로 맞춘 앱에서만
///   동작한다 — 웹과 모바일을 동시에 맞출 수는 없다.
/// - [oauthRedirect]: 공급자 페이지로 리다이렉트하고 인가 코드 교환은
///   **Supabase가 자기 REST API 키·시크릿으로** 수행한다. 클라이언트가
///   id_token을 만지지 않으므로 `aud` 불일치가 애초에 없고, 웹과 모바일이
///   설정 하나로 함께 동작한다. 카카오 콘솔에는 Supabase 콜백
///   (`https://<ref>.supabase.co/auth/v1/callback`)을 Redirect URI로 등록한다.
enum KakaoAuthFlow { idToken, oauthRedirect }

class KakaoAuthOptions {
  const KakaoAuthOptions({
    this.nativeAppKey = '',
    this.javaScriptAppKey = '',
    this.flow = KakaoAuthFlow.idToken,
  });

  final String nativeAppKey;
  final String javaScriptAppKey;

  /// 세션 발급 경로. 기본값은 기존 동작([KakaoAuthFlow.idToken])이다 —
  /// 이미 `aud`를 맞춰 둔 앱의 동작을 조용히 바꾸지 않기 위해서다.
  final KakaoAuthFlow flow;

  /// 실제 로그인이 가능한 설정인지.
  ///
  /// id_token 경로는 앱은 nativeAppKey, 웹은 javaScriptAppKey로 SDK를
  /// 초기화하므로 현재 플랫폼에 필요한 키가 있어야 한다. 리다이렉트 경로는
  /// 클라이언트가 카카오 SDK를 쓰지 않으므로 키 없이도 쓸 수 있다.
  bool get isUsable {
    if (flow == KakaoAuthFlow.oauthRedirect) return true;
    return kIsWeb
        ? javaScriptAppKey.trim().isNotEmpty
        : nativeAppKey.trim().isNotEmpty;
  }
}

/// Naver 자격 획득 설정. (Naver Developers > 애플리케이션 정보)
///
/// 웹은 인가 코드 리다이렉트 플로우([webRedirectUri]), 앱은 네이티브 SDK를 쓴다.
/// clientSecret은 앱(네이티브 SDK 초기화)과 서버 브로커에서만 사용된다 —
/// 네이버 네이티브 SDK 자체가 secret 내장을 요구하는 구조라는 점에 유의.
class NaverAuthOptions {
  const NaverAuthOptions({
    required this.clientId,
    this.clientSecret,
    this.clientName = '',
    this.webRedirectUri,
  });

  final String clientId;
  final String? clientSecret;
  final String clientName;

  /// 웹 리다이렉트 플로우의 redirect_uri. 미지정 시 현재 페이지 origin+path.
  final String? webRedirectUri;

  /// 실제 로그인이 가능한 설정인지 — clientId가 비어 있지 않아야 한다.
  bool get isUsable => clientId.trim().isNotEmpty;
}

/// Apple 자격 획득 설정. iOS 스토어 심사(4.8) 대응용 — iOS에서만 노출 권장.
class AppleAuthOptions {
  const AppleAuthOptions();

  /// Apple은 별도 클라이언트 키가 필요 없다(네이티브 Sign in with Apple).
  /// 노출 여부는 [LionAuthConfig.appleOnlyOnIos]의 플랫폼 게이트가 결정한다.
  bool get isUsable => true;
}

/// 회원가입 폼에 서비스별로 추가되는 커스텀 필드 정의.
/// (예: Nest의 닉네임/실명 수집)
class LionSignUpField {
  const LionSignUpField({
    required this.key,
    required this.label,
    this.hint = '',
    this.helper,
    this.required = true,
  });

  /// 백엔드 user metadata에 저장될 키. (예: 'full_name', 'real_name')
  final String key;
  final String label;
  final String hint;
  final String? helper;
  final bool required;
}

/// LionAuth 모듈의 서비스별 설정. 새 서비스는 이 객체만 채워서 주입한다.
class LionAuthConfig {
  const LionAuthConfig({
    required this.appName,
    this.brandLine = '',
    this.google,
    this.kakao,
    this.naver,
    this.apple,
    this.enableEmailPassword = true,
    this.extraSignUpFields = const [],
    this.appleOnlyOnIos = true,
  });

  final String appName;
  final String brandLine;

  final GoogleAuthOptions? google;
  final KakaoAuthOptions? kakao;
  final NaverAuthOptions? naver;
  final AppleAuthOptions? apple;

  /// 이메일/비밀번호 폼 노출 여부.
  final bool enableEmailPassword;

  /// 회원가입 시 추가 수집 필드.
  final List<LionSignUpField> extraSignUpFields;

  /// true면 Apple 버튼을 iOS(및 macOS)에서만 노출한다.
  final bool appleOnlyOnIos;

  /// 웹 OAuth 리다이렉트가 **돌아올 주소**.
  ///
  /// origin만으로 만들면 안 된다. 앱이 하위 경로에 배포되면(GitHub Pages
  /// 프로젝트 사이트의 `/fathom/` 등) 공급자는 사이트 루트로 돌려보내고
  /// 앱은 거기에 없다. 현재 문서의 **디렉터리까지**를 남긴다.
  ///
  /// 쿼리·프래그먼트는 떨군다 — 이전 로그인의 `?code=`가 묻어 가면 다음
  /// 복귀가 그 값을 다시 줍는다.
  static String webReturnUrl(Uri base) {
    final segments = List<String>.from(base.pathSegments);
    // `/fathom/` 처럼 슬래시로 끝나면 빈 조각이 붙는다.
    while (segments.isNotEmpty && segments.last.isEmpty) {
      segments.removeLast();
    }
    // 마지막 조각이 파일이면(`index.html`) 디렉터리까지만 남긴다.
    if (segments.isNotEmpty && segments.last.contains('.')) {
      segments.removeLast();
    }
    final path = segments.isEmpty ? '/' : '/${segments.join('/')}/';
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: path,
    ).toString();
  }

  /// **실제 로그인이 가능한**(=버튼을 노출할) 프로바이더 목록. 선언 순서 고정.
  ///
  /// 옵션 객체가 주입되어 있어도 키가 비어 있으면(콘솔 키 발급 전) 노출하지
  /// 않는다 — "동작하지 않는 소셜 버튼"을 원천 차단한다. 이 게이트가 있으므로
  /// 소비 측은 옵션을 항상 넘겨도 안전하다(빈 키 = 미노출).
  List<LionAuthProviderId> get enabledProviders => [
        if (google?.isUsable ?? false) LionAuthProviderId.google,
        if (kakao?.isUsable ?? false) LionAuthProviderId.kakao,
        if (naver?.isUsable ?? false) LionAuthProviderId.naver,
        if ((apple?.isUsable ?? false) &&
            (!appleOnlyOnIos ||
                defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.macOS))
          LionAuthProviderId.apple,
      ];

  /// 노출 가능한 소셜 프로바이더가 하나라도 있는지. 소셜 영역 자체의
  /// 표시 여부를 결정할 때 쓴다(전무하면 이메일 로그인만 깔끔하게 노출).
  bool get hasUsableSocialProvider => enabledProviders.isNotEmpty;
}
