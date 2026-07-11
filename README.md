# lion_auth

라이온앤더랩 공용 한국 특화 소셜 로그인 모듈 (Flutter).

Google · Kakao · Naver · Apple 로그인과 이메일 로그인을 하나의 완성 화면(`LionAuthScreen`)으로 제공한다.
자격 획득 코어(core)는 백엔드 비종속이며, 세션 발급은 `LionAuthBackend` 어댑터로 분리되어
Supabase 프로젝트든 자체 API 서버든 동일한 UI/상태 코드를 재사용할 수 있다.

## 구조

```
lib/
  lion_auth.dart                 # 단일 진입점 (이것만 import)
  src/
    config/    # LionAuthConfig(프로바이더 키·추가 가입 필드), LionAuthTheme(브랜드 색·폰트)
    core/      # SocialCredential + 프로바이더별 자격 획득 (Google/Kakao/Naver/Apple, 웹+앱)
    backend/   # LionAuthBackend 계약 + SupabaseLionAuthBackend / HttpLionAuthBackend
    state/     # LionAuthController (ChangeNotifier)
    ui/        # LionAuthScreen (완성 로그인 화면) + 브랜드 소셜 버튼
server/
  supabase/functions/social-broker/   # Naver 등 Supabase 미지원 프로바이더 세션 중개 Edge Function
test/        # 위젯/설정 테스트
SETUP.md     # 콘솔 4곳(Google/Kakao/Naver/Apple) 키 발급 가이드 + .env 스키마
```

## 서브모듈로 사용하기

호스트 프로젝트 루트에서:

```bash
git submodule add https://github.com/lionandthelab/lion_auth.git packages/lion_auth
git submodule update --init
```

앱의 `pubspec.yaml`에 경로 의존성 추가 (앱 위치에 따라 상대 경로 조정):

```yaml
dependencies:
  lion_auth:
    path: ../packages/lion_auth
```

클론 시에는 `git clone --recurse-submodules`, 갱신 시에는:

```bash
git submodule update --remote packages/lion_auth   # 최신 main으로 이동
git add packages/lion_auth && git commit            # 호스트에 SHA 고정 커밋
```

> 이 레포는 private이므로 CI에서 서브모듈을 클론하려면 read-only 배포 키(또는 PAT)가 필요하다.
> GitHub Actions 예시는 아래 [CI 체크아웃](#ci-체크아웃) 참고.

## 최소 사용 예 (Supabase)

```dart
import 'package:lion_auth/lion_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final controller = LionAuthController(
  config: LionAuthConfig(
    appName: '내 앱',
    google: GoogleAuthOptions(webClientId: '...'),
    kakao: KakaoAuthOptions(nativeAppKey: '...', javaScriptAppKey: '...'),
    naver: NaverAuthOptions(clientId: '...', clientName: '내 앱'),
    apple: const AppleAuthOptions(), // 기본값: iOS에서만 노출
    // 회원가입 시 추가 수집 필드 (닉네임/실명 등)
    extraSignUpFields: const [
      LionSignUpField(key: 'full_name', label: '닉네임'),
    ],
  ),
  backend: SupabaseLionAuthBackend(Supabase.instance.client),
);

// 라우팅에서:
LionAuthScreen(
  controller: controller,
  theme: const LionAuthTheme(primary: Color(0xFFDCAE96)),
)
```

- 키가 없는 프로바이더는 `null`로 두면 버튼이 노출되지 않는다 (`enabledProviders`가 키 유효성으로 게이트).
- 로그인 성공 여부는 `controller.isLoggedIn` / `controller.session`으로 구독한다 (`AnimatedBuilder` 등).
- Supabase가 아닌 자체 서버는 `HttpLionAuthBackend`를 사용한다 (계약은 `lib/src/backend/http_auth_backend.dart` 참조).

## Naver 브로커 (Supabase 전용)

Naver는 Supabase가 기본 지원하지 않으므로 `server/supabase/functions/social-broker`를
호스트 프로젝트의 Supabase에 배포해야 한다. 배포·시크릿 설정은 `SETUP.md`와
호스트 프로젝트의 셋업 스크립트(예: nest의 `scripts/lion_auth_setup.mjs`)를 참고.

## CI 체크아웃

read-only 배포 키를 이 레포에 등록하고, 호스트 레포 시크릿(예: `LION_AUTH_DEPLOY_KEY`)에
개인 키를 넣은 뒤:

```yaml
- uses: actions/checkout@v4
  with:
    submodules: recursive
    ssh-key: ${{ secrets.LION_AUTH_DEPLOY_KEY }}
```

`ssh-key`를 지정하면 actions/checkout이 `https://github.com/` URL을 SSH로 자동 재작성하므로
`.gitmodules`의 https URL을 바꿀 필요가 없다.

## 검증

```bash
flutter test           # 패키지 단독 위젯/설정 테스트
```

전체 플로우(실 키 주입) 검증 하네스는 nest 프로젝트의 `frontend/lib/main_auth_lab.dart`
+ `scripts/run_auth_lab.mjs`를 참조.

## 사용 중인 프로젝트

| 프로젝트 | 경로 | 백엔드 |
|---|---|---|
| nest | `packages/lion_auth` | Supabase (`SupabaseLionAuthBackend`) |
| ttobak | `packages/lion_auth` | Supabase (`SupabaseLionAuthBackend`) |
