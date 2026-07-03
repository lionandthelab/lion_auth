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
  });

  final String webClientId;
  final String? iosClientId;
}

/// Kakao 자격 획득 설정. (Kakao Developers > 앱 키)
///
/// 카카오 로그인 + OpenID Connect 활성화가 선행되어야 id_token이 발급된다.
class KakaoAuthOptions {
  const KakaoAuthOptions({
    required this.nativeAppKey,
    required this.javaScriptAppKey,
  });

  final String nativeAppKey;
  final String javaScriptAppKey;
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
}

/// Apple 자격 획득 설정. iOS 스토어 심사(4.8) 대응용 — iOS에서만 노출 권장.
class AppleAuthOptions {
  const AppleAuthOptions();
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

  /// 설정이 존재하는(=버튼을 노출할) 프로바이더 목록. 선언 순서 고정.
  List<LionAuthProviderId> get enabledProviders => [
        if (google != null) LionAuthProviderId.google,
        if (kakao != null) LionAuthProviderId.kakao,
        if (naver != null) LionAuthProviderId.naver,
        if (apple != null &&
            (!appleOnlyOnIos ||
                defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.macOS))
          LionAuthProviderId.apple,
      ];
}
