// 카카오 로그인이 Supabase 검증을 통과할 수 있는 형태인가.
//
// 배경: `signInWithIdToken` 은 id_token 의 `aud` 가 Supabase 의
// `external_kakao_client_id` 와 같아야 통과한다. 그런데 카카오 SDK 는
// **플랫폼마다 다른 키**로 인가를 요청한다:
//
//     KakaoSdk.appKey => kIsWeb ? javaScriptAppKey : nativeAppKey
//
// Supabase 콘솔이 받는 값은 보통 **REST API 키** 한 개다. 세 키가 모두 다르니
// 웹·모바일 양쪽에서 aud 불일치로 거절된다. 커스텀 스킴 리다이렉트는 카카오
// 콘솔의 Redirect URI 에 등록할 수 없어서 "REST 키로 통일" 도 성립하지 않는다.
//
// 그래서 플로우를 **설정으로** 고른다. 기본은 기존 동작(idToken)을 유지해
// 이미 aud 를 맞춰 둔 앱을 깨뜨리지 않고, 웹·모바일을 한 설정으로 돌리려는
// 앱은 oauthRedirect 를 고른다 — 코드 교환을 Supabase 가 자기 REST 키로
// 수행하므로 aud 문제가 애초에 없다.

import 'package:flutter_test/flutter_test.dart';
import 'package:lion_auth/lion_auth.dart';

void main() {
  group('카카오 플로우 선택', () {
    test('기본은 id_token — 기존 앱의 동작을 바꾸지 않는다', () {
      const options = KakaoAuthOptions(
        nativeAppKey: 'native',
        javaScriptAppKey: 'js',
      );
      expect(options.flow, KakaoAuthFlow.idToken);
    });

    test('oauthRedirect 를 고르면 그 값이 유지된다', () {
      const options = KakaoAuthOptions(
        nativeAppKey: 'native',
        javaScriptAppKey: 'js',
        flow: KakaoAuthFlow.oauthRedirect,
      );
      expect(options.flow, KakaoAuthFlow.oauthRedirect);
    });

    test('리다이렉트 플로우에서는 앱 키가 없어도 버튼이 뜬다', () {
      // 코드 교환을 Supabase 가 하므로 클라이언트에 키가 필요 없다.
      // 키 유무로 버튼을 가리면 "설정했는데 버튼이 없다" 가 된다.
      const options = KakaoAuthOptions(
        nativeAppKey: '',
        javaScriptAppKey: '',
        flow: KakaoAuthFlow.oauthRedirect,
      );
      expect(options.isUsable, isTrue);
    });

    test('id_token 플로우는 플랫폼 키가 있어야 쓸 수 있다', () {
      const noKeys = KakaoAuthOptions(nativeAppKey: '', javaScriptAppKey: '');
      expect(noKeys.isUsable, isFalse);
    });
  });

  group('컨트롤러 배선', _controllerWiring);

  group('웹 리다이렉트 복귀 주소', () {
    test('배포 경로(base href)를 잃지 않는다', () {
      // GitHub Pages 프로젝트 사이트처럼 앱이 하위 경로에 배포되면
      // origin 만으로 복귀 주소를 만들 때 `/fathom/` 이 통째로 사라진다.
      // 그러면 공급자는 사이트 루트로 돌려보내고 앱은 거기에 없다.
      expect(
        LionAuthConfig.webReturnUrl(
          Uri.parse('https://lionandthelab.github.io/fathom/#/auth'),
        ),
        'https://lionandthelab.github.io/fathom/',
      );
    });

    test('루트 배포는 그대로 루트다', () {
      expect(
        LionAuthConfig.webReturnUrl(Uri.parse('https://gomgom.app/#/auth')),
        'https://gomgom.app/',
      );
    });

    test('쿼리와 프래그먼트는 떨군다', () {
      // 복귀 주소에 이전 로그인의 ?code= 가 묻어 가면 다음 복귀가 꼬인다.
      expect(
        LionAuthConfig.webReturnUrl(
          Uri.parse('https://lionandthelab.github.io/fathom/?code=abc#/auth'),
        ),
        'https://lionandthelab.github.io/fathom/',
      );
    });

    test('파일 경로로 끝나도 디렉터리까지만 남긴다', () {
      expect(
        LionAuthConfig.webReturnUrl(
          Uri.parse('https://example.com/app/index.html'),
        ),
        'https://example.com/app/',
      );
    });
  });
}

// ── 컨트롤러 배선 ─────────────────────────────────────────────────────────

class _RecordingBackend implements LionAuthBackend {
  final List<String> redirects = <String>[];
  final List<LionAuthProviderId> credentials = <LionAuthProviderId>[];

  @override
  Future<void> signInWithOAuthRedirect(
    LionAuthProviderId provider, {
    String? redirectTo,
  }) async {
    redirects.add('${provider.name}:${redirectTo ?? '-'}');
  }

  @override
  Future<LionAuthSession> signInWithCredential(SocialCredential c) async {
    credentials.add(c.provider);
    return const LionAuthSession(userId: 'u1');
  }

  @override
  Future<LionAuthSession> signInWithPassword({
    required String email,
    required String password,
  }) async =>
      const LionAuthSession(userId: 'u1');

  @override
  Future<LionAuthSession> signUpWithPassword({
    required String email,
    required String password,
    Map<String, dynamic> metadata = const {},
  }) async =>
      const LionAuthSession(userId: 'u1');

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async {}
}

void _controllerWiring() {
  test('oauthRedirect 설정이면 카카오 탭은 리다이렉트로 간다', () async {
    final backend = _RecordingBackend();
    final controller = LionAuthController(
      config: const LionAuthConfig(
        appName: 't',
        kakao: KakaoAuthOptions(flow: KakaoAuthFlow.oauthRedirect),
      ),
      backend: backend,
    );
    addTearDown(controller.dispose);

    await controller.signInWithSocial(LionAuthProviderId.kakao);

    expect(backend.redirects.single, startsWith('kakao:'),
        reason: 'id_token 경로로 가면 aud 불일치로 Supabase 가 거절한다');
    expect(backend.credentials, isEmpty);
  });

  test('모바일 복귀 주소는 앱 딥링크다', () async {
    // redirectTo 를 비우면 GoTrue 는 site_url 로 돌려보낸다. 그건 보통
    // 마케팅 도메인이라 앱은 세션을 영영 받지 못하고, 사용자는 브라우저에
    // 남는다. 앱이 돌아올 자리를 명시한다.
    final backend = _RecordingBackend();
    final controller = LionAuthController(
      config: const LionAuthConfig(
        appName: 't',
        mobileRedirectUri: 'fathom://login-callback/',
        kakao: KakaoAuthOptions(flow: KakaoAuthFlow.oauthRedirect),
      ),
      backend: backend,
    );
    addTearDown(controller.dispose);

    await controller.signInWithSocial(LionAuthProviderId.kakao);

    // 테스트는 웹이 아니므로 모바일 분기를 탄다.
    expect(backend.redirects.single, 'kakao:fathom://login-callback/');
  });

  test('딥링크를 안 주면 비워서 보낸다 — 기존 동작', () async {
    final backend = _RecordingBackend();
    final controller = LionAuthController(
      config: const LionAuthConfig(
        appName: 't',
        kakao: KakaoAuthOptions(flow: KakaoAuthFlow.oauthRedirect),
      ),
      backend: backend,
    );
    addTearDown(controller.dispose);

    await controller.signInWithSocial(LionAuthProviderId.kakao);
    expect(backend.redirects.single, 'kakao:-');
  });

  test('기본(idToken) 설정에서는 리다이렉트를 쓰지 않는다', () async {
    final backend = _RecordingBackend();
    final controller = LionAuthController(
      config: const LionAuthConfig(
        appName: 't',
        kakao: KakaoAuthOptions(
          nativeAppKey: 'native',
          javaScriptAppKey: 'js',
        ),
      ),
      backend: backend,
    );
    addTearDown(controller.dispose);

    await controller.signInWithSocial(LionAuthProviderId.kakao);

    expect(backend.redirects, isEmpty,
        reason: '기존 앱의 경로를 조용히 바꾸면 안 된다');
  });
}
