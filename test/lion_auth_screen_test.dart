import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lion_auth/lion_auth.dart';

/// 백엔드 없이 화면/컨트롤러 동작을 검증하기 위한 페이크.
class _FakeBackend implements LionAuthBackend {
  final List<String> calls = [];
  Map<String, dynamic>? lastSignUpMetadata;
  bool failPasswordSignIn = false;

  @override
  Future<LionAuthSession> signInWithCredential(SocialCredential credential) {
    calls.add('social:${credential.provider.name}');
    return Future.value(
      LionAuthSession(userId: 'u1', provider: credential.provider.name),
    );
  }

  @override
  Future<LionAuthSession> signInWithPassword({
    required String email,
    required String password,
  }) {
    calls.add('password:$email');
    if (failPasswordSignIn) {
      throw const LionAuthBackendException('이메일 또는 비밀번호가 올바르지 않습니다.');
    }
    return Future.value(
      LionAuthSession(userId: 'u1', email: email, provider: 'email'),
    );
  }

  @override
  Future<LionAuthSession> signUpWithPassword({
    required String email,
    required String password,
    Map<String, dynamic> metadata = const {},
  }) {
    calls.add('signup:$email');
    lastSignUpMetadata = metadata;
    return Future.value(
      LionAuthSession(
        userId: 'u2',
        email: email,
        provider: 'email',
        isNewUser: true,
        metadata: metadata,
      ),
    );
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    calls.add('reset:$email');
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
  }
}

LionAuthConfig _config() => const LionAuthConfig(
      appName: '테스트 서비스',
      brandLine: '모듈 검증',
      kakao: KakaoAuthOptions(nativeAppKey: 'test-key', javaScriptAppKey: 'js'),
      naver: NaverAuthOptions(clientId: 'naver-id'),
      extraSignUpFields: [
        LionSignUpField(key: 'full_name', label: '닉네임'),
        LionSignUpField(key: 'real_name', label: '실명'),
      ],
    );

void main() {
  testWidgets('로그인 화면 기본 구성 렌더링 (이메일 폼 + 소셜 버튼)', (tester) async {
    final backend = _FakeBackend();
    final controller = LionAuthController(config: _config(), backend: backend);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: LionAuthScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('테스트 서비스'), findsOneWidget);
    expect(find.byKey(const ValueKey('lion_auth_email')), findsOneWidget);
    expect(find.byKey(const ValueKey('lion_auth_password')), findsOneWidget);
    expect(find.byKey(const ValueKey('lion_auth_social_kakao')), findsOneWidget);
    expect(find.byKey(const ValueKey('lion_auth_social_naver')), findsOneWidget);
    expect(find.byKey(const ValueKey('lion_auth_social_google')), findsNothing);
  });

  testWidgets('이메일 로그인 성공 시 onAuthenticated 호출', (tester) async {
    final backend = _FakeBackend();
    LionAuthSession? authenticated;
    final controller = LionAuthController(
      config: _config(),
      backend: backend,
      onAuthenticated: (session) => authenticated = session,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: LionAuthScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('lion_auth_email')), 'user@test.com');
    await tester.enterText(
      find.byKey(const ValueKey('lion_auth_password')), 'secret1');
    await tester.tap(find.byKey(const ValueKey('lion_auth_submit')));
    await tester.pumpAndSettle();

    expect(backend.calls, contains('password:user@test.com'));
    expect(authenticated?.userId, 'u1');
    expect(controller.isLoggedIn, isTrue);
  });

  testWidgets('로그인 실패 시 한국어 에러 배너 노출', (tester) async {
    final backend = _FakeBackend()..failPasswordSignIn = true;
    final controller = LionAuthController(config: _config(), backend: backend);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: LionAuthScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('lion_auth_email')), 'user@test.com');
    await tester.enterText(
      find.byKey(const ValueKey('lion_auth_password')), 'wrong1');
    await tester.tap(find.byKey(const ValueKey('lion_auth_submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('lion_auth_error')), findsOneWidget);
    expect(find.text('이메일 또는 비밀번호가 올바르지 않습니다.'), findsOneWidget);
    expect(controller.isLoggedIn, isFalse);
  });

  testWidgets('회원가입 모드에서 추가 필드 수집 → metadata 전달', (tester) async {
    final backend = _FakeBackend();
    final controller = LionAuthController(config: _config(), backend: backend);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: LionAuthScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('lion_auth_toggle_mode')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('lion_auth_confirm')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('lion_auth_extra_full_name')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('lion_auth_extra_real_name')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('lion_auth_email')), 'new@test.com');
    await tester.enterText(
      find.byKey(const ValueKey('lion_auth_password')), 'secret1');
    await tester.enterText(
      find.byKey(const ValueKey('lion_auth_confirm')), 'secret1');
    await tester.enterText(
      find.byKey(const ValueKey('lion_auth_extra_full_name')), '둥지지기');
    await tester.enterText(
      find.byKey(const ValueKey('lion_auth_extra_real_name')), '홍길동');
    await tester.ensureVisible(find.byKey(const ValueKey('lion_auth_submit')));
    await tester.tap(find.byKey(const ValueKey('lion_auth_submit')));
    await tester.pumpAndSettle();

    expect(backend.calls, contains('signup:new@test.com'));
    expect(backend.lastSignUpMetadata, {
      'full_name': '둥지지기',
      'real_name': '홍길동',
    });
  });

  test('LionAuthConfig.enabledProviders는 설정된 프로바이더만 노출', () {
    expect(
      _config().enabledProviders,
      [LionAuthProviderId.kakao, LionAuthProviderId.naver],
    );
    const full = LionAuthConfig(
      appName: 'x',
      google: GoogleAuthOptions(webClientId: 'w'),
      kakao: KakaoAuthOptions(nativeAppKey: 'n', javaScriptAppKey: 'j'),
      naver: NaverAuthOptions(clientId: 'c'),
      apple: AppleAuthOptions(),
      appleOnlyOnIos: false,
    );
    expect(full.enabledProviders, [
      LionAuthProviderId.google,
      LionAuthProviderId.kakao,
      LionAuthProviderId.naver,
      LionAuthProviderId.apple,
    ]);
  });

  test('빈/공백 키의 프로바이더는 노출하지 않는다 (동작 불가 버튼 차단)', () {
    // 옵션은 주입됐지만 콘솔 키가 비어 있는 경우 — 버튼을 노출하면 눌러도
    // 실패하므로, enabledProviders에서 제외되어야 한다.
    const blank = LionAuthConfig(
      appName: 'x',
      google: GoogleAuthOptions(webClientId: '   '),
      kakao: KakaoAuthOptions(nativeAppKey: '', javaScriptAppKey: ''),
      naver: NaverAuthOptions(clientId: ''),
      apple: AppleAuthOptions(),
      appleOnlyOnIos: false, // 플랫폼 게이트 배제하고 키 게이트만 검증
    );
    expect(
      blank.enabledProviders,
      [LionAuthProviderId.apple], // 키가 필요 없는 Apple만 남는다
    );

    const noneUsable = LionAuthConfig(
      appName: 'x',
      google: GoogleAuthOptions(webClientId: ''),
      kakao: KakaoAuthOptions(nativeAppKey: '', javaScriptAppKey: ''),
      naver: NaverAuthOptions(clientId: ''),
    );
    expect(noneUsable.enabledProviders, isEmpty);
    expect(noneUsable.hasUsableSocialProvider, isFalse);
  });
}
