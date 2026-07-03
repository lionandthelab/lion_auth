# lion_auth 셋업 가이드

한국 특화 소셜 로그인(Google · Kakao · Naver · Apple) 공용 모듈.
**수동 작업은 "각 콘솔에서 키 발급" 딱 한 번**이고, 나머지는 `.env`를 채운 뒤 스크립트가 전부 자동으로 처리한다.

```
[1회 수동] 콘솔 4곳 키 발급  →  [.env 채움]  →  node scripts/lion_auth_setup.mjs all
                                              →  node scripts/run_auth_lab.mjs (검증)
```

## 아키텍처 한 장 요약

```
LionAuthScreen (ui)                  ← 완성형 로그인/가입 화면, 테마 주입
  └ LionAuthController (state)
      ├ SocialCredentialProvider (core)   ← 자격 획득. 백엔드와 무관
      │   ├ Google: 앱=네이티브 시트, 웹=GIS 공식 버튼
      │   ├ Kakao : 앱=카카오톡 앱투앱, 웹=카카오계정 (OIDC id_token)
      │   ├ Naver : 앱=네이티브 SDK, 웹=인가코드 리다이렉트
      │   └ Apple : iOS 전용 (심사 지침 4.8 대응)
      └ LionAuthBackend (backend)         ← 세션 발급 어댑터
          ├ SupabaseLionAuthBackend  (Nest 등 Supabase 서비스)
          │   └ naver만 Edge Function social-broker 경유
          └ HttpLionAuthBackend      (GCloud VM 등 자체 서버, 계약은 아래)
```

---

## 1단계 — 콘솔 키 발급 (서비스당 1회 수동)

각 콘솔은 앱 등록 API를 제공하지 않아 이 단계만 수동이다.
**아래 프롬프트를 브라우저 에이전트(Claude in Chrome 등)에 그대로 붙여넣으면 대신 처리할 수 있다.**
프롬프트의 `{{ }}` 부분만 미리 채워 넣을 것.

### 서비스별 공통 값 (Nest 기준 — 새 서비스는 여기만 교체)

| 항목 | 값 |
|---|---|
| 앱 이름 | Nest |
| Android 패키지 / iOS 번들 | `com.lionandthelab.nest` |
| Supabase 콜백 | `https://avursvhmilcsssabqtkx.supabase.co/auth/v1/callback` |
| 로컬 개발 URL | `http://localhost:8080` |
| 프로덕션 웹 | `https://nestapp.life/` (origin: `https://nestapp.life`) |
| 개인정보처리방침 URL | `https://nestapp.life/privacy.html` |
| 이용약관 URL | `https://nestapp.life/terms.html` |

> 개인정보처리방침·이용약관 페이지는 `frontend/assets/legal/*.md`(단일 소스)에서
> 관리하며, `node scripts/render_legal.mjs`가 위 URL의 정적 HTML을 생성한다.
> OAuth 콘솔 3사 모두 이 URL을 요구하므로 아래 프롬프트에 이미 포함되어 있다.

**Android 서명 지문·키 해시 얻기 (프롬프트에 붙여넣을 값, PowerShell):**

- **Google은 SHA-1 지문**, **Kakao는 키 해시**(= `base64(SHA-1(서명 인증서))`, 끝이 `=`인 28자 문자열)를 요구한다.
- Kakao는 앱을 서명한 **모든 인증서의 키 해시**를 등록해야 하며, 하나라도 빠지면 그 빌드에서 카카오 API 호출(로그인 포함)이 막힌다. 등록 대상 3종:
  1. **디버그 키 해시** — 개발/에뮬레이터(안드로이드 스튜디오 자동 생성 인증서)
  2. **릴리즈 키 해시** — 직접 서명해 배포할 때(내 릴리즈 키스토어)
  3. **Google Play 앱 서명 키 해시** — Play 스토어(AAB) 배포 시 Google이 앱을 **재서명**하므로 이게 실제 프로덕션 해시다. 로컬 키스토어로는 구할 수 없다. **빠뜨리면 "개발/내부테스트는 되는데 스토어 배포 후 카카오 로그인 실패"의 전형적 원인.**

```powershell
# --- Google용 SHA-1 지문 (디버그) ---
keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android | Select-String "SHA1"

# --- Kakao 디버그 키 해시 (openssl 필요) ---
keytool -exportcert -alias androiddebugkey -keystore "$env:USERPROFILE\.android\debug.keystore" -storepass android | openssl sha1 -binary | openssl base64

# --- Kakao 릴리즈 키 해시 (직접 서명 배포용, openssl 필요) ---
keytool -exportcert -alias <릴리즈_별칭> -keystore <릴리즈_키스토어_경로> | openssl sha1 -binary | openssl base64
```

**Google Play 앱 서명 키 해시** (openssl 불필요): Google Play Console → **설정 > 앱 무결성 > 앱 서명** 의 *앱 서명 키 인증서* SHA-1 지문을 복사한 뒤, hex → base64로 변환한다.

```powershell
# 콘솔에서 복사한 SHA-1 (콜론 포함/미포함 무관)
$sha1  = "AB:CD:EF:...:12:34"
$hex   = ($sha1 -replace '[^0-9A-Fa-f]', '')
$bytes = [byte[]]::new($hex.Length / 2)
for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16) }
[Convert]::ToBase64String($bytes)   # ← 이 28자 문자열이 카카오 키 해시
```

> 이 hex→base64 변환은 어떤 SHA-1에도 쓸 수 있다. openssl이 없으면 위 `keytool -list -v` 의
> SHA1 값을 그대로 `$sha1`에 넣어 디버그/릴리즈 키 해시도 openssl 없이 구할 수 있다.

### 1-A. Google Cloud Console — 브라우저 에이전트 프롬프트

```text
Google Cloud Console(https://console.cloud.google.com)에서 다음 작업을 수행해줘.
프로젝트가 없으면 "nest-lionandthelab" 이름으로 새로 만들어줘.

1. [API 및 서비스 > OAuth 동의 화면]이 미구성 상태면:
   - User Type: 외부, 앱 이름: Nest, 지원 이메일: {{내 이메일}}
   - 애플리케이션 홈페이지: https://nestapp.life/
   - 개인정보처리방침 링크: https://nestapp.life/privacy.html
   - 서비스 약관 링크: https://nestapp.life/terms.html
   - 게시 상태를 "프로덕션"으로 (또는 테스트 사용자에 {{내 이메일}} 추가)

2. [API 및 서비스 > 사용자 인증 정보 > 사용자 인증 정보 만들기 > OAuth 클라이언트 ID]로
   아래 3개의 클라이언트를 만들어줘:

   (1) 유형: 웹 애플리케이션, 이름: "Nest Web"
       - 승인된 자바스크립트 원본: http://localhost:8080 , https://nestapp.life
       - 승인된 리디렉션 URI: https://avursvhmilcsssabqtkx.supabase.co/auth/v1/callback
   (2) 유형: Android, 이름: "Nest Android"
       - 패키지 이름: com.lionandthelab.nest
       - SHA-1 인증서 지문: {{SHA1 값}}
   (3) 유형: iOS, 이름: "Nest iOS"
       - 번들 ID: com.lionandthelab.nest

3. 작업이 끝나면 결과를 정확히 아래 형식으로 출력해줘
   (웹 클라이언트의 보안 비밀번호도 포함):

LION_GOOGLE_WEB_CLIENT_ID=<웹 클라이언트 ID>
LION_GOOGLE_WEB_CLIENT_SECRET=<웹 클라이언트 보안 비밀번호>
LION_GOOGLE_ANDROID_CLIENT_ID=<Android 클라이언트 ID>
LION_GOOGLE_IOS_CLIENT_ID=<iOS 클라이언트 ID>
```

### 1-B. Kakao Developers — 브라우저 에이전트 프롬프트

```text
Kakao Developers(https://developers.kakao.com)에 로그인해서 다음 작업을 수행해줘.

1. [내 애플리케이션 > 애플리케이션 추가하기]
   - 앱 이름: Nest, 회사명: 라이온앤더랩, 카테고리: 교육
   - [앱 설정 > 일반]의 개인정보처리방침 URL(있으면):
     https://nestapp.life/privacy.html

2. [앱 설정 > 플랫폼]에 3개 플랫폼 등록:
   - Web: 사이트 도메인에 http://localhost:8080 와 https://nestapp.life 추가
   - Android: 패키지명 com.lionandthelab.nest
     키 해시: {{디버그 키 해시}}  (스토어 배포 전 {{Play 앱 서명 키 해시}}도 추가 등록 — 위 '키 해시 얻기' 참고)
   - iOS: 번들 ID com.lionandthelab.nest

3. [제품 설정 > 카카오 로그인]
   - 활성화 설정: ON
   - Redirect URI 등록:
     https://avursvhmilcsssabqtkx.supabase.co/auth/v1/callback
     http://localhost:8080
     https://nestapp.life/
   - [카카오 로그인 > OpenID Connect] 활성화: ON  ← 매우 중요

4. [제품 설정 > 카카오 로그인 > 동의항목]
   - 닉네임, 프로필 사진: 필수 동의
   - 카카오계정(이메일): 선택 동의로 등록
     (이메일을 '필수 동의'로 두려면 비즈니스 앱 전환[사업자 정보 등록]이 필요하다.
      미전환 상태에서는 선택 동의만 가능하며, 앱은 이메일 미제공 계정도 처리해야 한다.)

5. [앱 설정 > 보안]에서 Client Secret 코드 생성 후 "사용함" 상태로 변경

6. 결과를 정확히 아래 형식으로 출력해줘 ([앱 설정 > 앱 키]에서 확인):

LION_KAKAO_NATIVE_APP_KEY=<네이티브 앱 키>
LION_KAKAO_JS_KEY=<JavaScript 키>
LION_KAKAO_REST_API_KEY=<REST API 키>
LION_KAKAO_CLIENT_SECRET=<보안 탭의 Client Secret>
```

### 1-C. Naver Developers — 브라우저 에이전트 프롬프트

```text
Naver Developers(https://developers.naver.com/apps)에 로그인해서 다음 작업을 수행해줘.

1. [Application > 애플리케이션 등록]
   - 애플리케이션 이름: Nest
   - 사용 API: 네이버 로그인
   - 제공 정보 선택: 이메일 주소(필수), 이름(필수), 별명, 프로필 사진
   - (검수 신청 시) 개인정보 수집 및 이용 안내 URL:
     https://nestapp.life/privacy.html

2. [로그인 오픈 API 서비스 환경]에 아래 환경들을 모두 추가:
   - PC 웹:
     서비스 URL: http://localhost:8080
     네이버 로그인 Callback URL:
       http://localhost:8080
       https://nestapp.life/
   - Android:
     패키지 이름: com.lionandthelab.nest
     다운로드 URL: https://nestapp.life/ (스토어 등록 전 임시)
   - iOS:
     번들 ID: com.lionandthelab.nest
     URL Scheme: nestnaverlogin

3. 등록 완료 후 결과를 정확히 아래 형식으로 출력해줘:

LION_NAVER_CLIENT_ID=<Client ID>
LION_NAVER_CLIENT_SECRET=<Client Secret>
```

### 1-D. Supabase 액세스 토큰 — 브라우저 에이전트 프롬프트

```text
https://supabase.com/dashboard/account/tokens 에 로그인해서
"lion_auth setup" 이라는 이름으로 액세스 토큰을 새로 생성하고,
생성된 토큰(sbp_로 시작)을 아래 형식으로 출력해줘:

SUPABASE_ACCESS_TOKEN=<토큰>
SUPABASE_PROJECT_REF=avursvhmilcsssabqtkx
```

> Apple 로그인은 iOS 스토어 제출 시점에 추가한다 (Apple Developer 콘솔 + Supabase Apple provider).
> 이 모듈의 Apple 버튼은 iOS에서만 노출되므로 웹/Android 검증에는 필요 없다.

---

## 2단계 — .env 채우기

브라우저 에이전트가 출력한 값들을 저장소 루트 `.env`에 붙여넣는다.
스키마 전체는 [`.env.example`](.env.example) 참고.

---

## 3단계 — 자동 셋업 (대시보드 클릭 불필요)

```powershell
node scripts/lion_auth_setup.mjs all      # 아래 전부 실행
# 또는 개별:
node scripts/lion_auth_setup.mjs doctor   # .env/서버 설정 상태 진단
node scripts/lion_auth_setup.mjs supabase # Management API로 Google/Kakao provider 설정 + Naver 시크릿 주입
node scripts/lion_auth_setup.mjs android  # AndroidManifest.xml에 Kakao 스킴/Naver meta-data 주입
node scripts/lion_auth_setup.mjs ios      # Info.plist에 URL 스킴/Nid* 키 주입
node scripts/lion_auth_setup.mjs broker   # social-broker Edge Function 배포 (supabase CLI)
```

Supabase 설정은 Management API(`PATCH /v1/projects/{ref}/config/auth`)로 처리되므로
대시보드에 들어갈 필요가 없다. 스크립트는 마커 주석(`lion_auth:begin/end`) 기반이라
여러 번 실행해도 안전(멱등)하다.

---

## 4단계 — 독립 검증 (기존 로그인 전환 전 필수)

> **철칙: auth-lab에서 전체 플로우가 검증되기 전에는 기존 로그인 화면을 절대 바꾸지 않는다.**

```powershell
# 웹 (Chrome, http://localhost:8080)
node scripts/run_auth_lab.mjs

# Android 에뮬레이터
node scripts/run_auth_lab.mjs -d emulator-5554

# 웹 릴리스 빌드만 (headless 스모크 테스트용)
node scripts/run_auth_lab.mjs --build
```

검증 체크리스트:

- [ ] 웹: 이메일 로그인/가입 (기존 계정으로)
- [ ] 웹: Google (GIS 버튼) → 세션 패널에 provider=google 표시
- [ ] 웹: Kakao (팝업) → provider=kakao
- [ ] 웹: Naver (리다이렉트 → 복귀) → provider=naver
- [ ] Android 에뮬레이터: Google 네이티브 시트 / 카카오 계정 로그인 / 네이버 로그인
- [ ] 기존 이메일 가입 계정과 같은 이메일의 소셜 로그인 → 같은 userId로 연결되는지
- [ ] 소셜 첫 로그인 계정에 real_name 없음 확인 (→ 전환 시 프로필 보완 스텝 필요)

---

## HttpLionAuthBackend 서버 계약 (비-Supabase 서비스용)

모든 요청/응답은 JSON. 실패 시 `{"error": "<한국어 메시지>"}`.

| 엔드포인트 | 요청 | 성공 응답 |
|---|---|---|
| `POST /auth/social` | `{provider, id_token?, access_token?, auth_code?, redirect_uri?, state?}` | 아래 공통 |
| `POST /auth/sign-in` | `{email, password}` | 아래 공통 |
| `POST /auth/sign-up` | `{email, password, metadata}` | 아래 공통 |
| `POST /auth/password-reset` | `{email}` | `{}` |

공통 성공 응답:

```json
{
  "user": {"id": "...", "email": "...", "display_name": "...", "metadata": {}},
  "is_new_user": false,
  "access_token": "(서비스 자체 JWT — 자유 형식)"
}
```

서버는 프로바이더 토큰을 반드시 검증해야 한다:
- google/kakao/apple: id_token의 서명·audience·만료 검증 (각사 JWKS)
- naver: `auth_code`를 client_secret으로 교환 후 `openapi.naver.com/v1/nid/me` 조회

---

## 트러블슈팅

| 증상 | 원인/해결 |
|---|---|
| Kakao `KOE006` | Redirect URI 미등록 — 에러 화면에 표시된 URI를 콘솔에 그대로 등록 |
| Kakao `KOE101` / Android 로그인 직후 튕김 | 키 해시 미등록·불일치 — 해당 빌드 서명의 키 해시를 콘솔 Android 플랫폼에 등록 |
| Kakao 스토어 배포 후에만 로그인 실패 (개발·내부테스트는 정상) | Google Play 앱 서명 키 해시 미등록 — Play Console SHA-1을 base64 변환해 추가 |
| Kakao 이메일 미수신 / '필수 동의' 설정 불가 | 이메일 필수 동의는 비즈니스 앱 전환 필요 — 미전환 시 선택 동의 + 앱에서 이메일 없는 계정 처리 |
| Kakao 로그인 후 `카카오 ID 토큰이 없습니다` | OpenID Connect 비활성 — 콘솔에서 활성화 |
| Supabase `provider is not enabled` | `lion_auth_setup.mjs supabase` 미실행 또는 실패 |
| Google 웹 버튼이 안 보임 | `LION_GOOGLE_WEB_CLIENT_ID` 미주입, 또는 origin 미등록 |
| Supabase Kakao id_token 거부 (audience) | Supabase Kakao provider의 Client ID에 REST API 키 외에 네이티브/JS 키 추가 필요 여부 확인 (doctor 출력 참고) |
| Naver `이메일 제공에 동의해 주세요` | 네이버 콘솔 제공 정보에서 이메일을 필수로, 사용자 재동의 필요 |
| 웹 Naver 복귀 후 아무 일 없음 | Callback URL이 현재 페이지 URL과 정확히 일치하는지 확인 (포트 포함) |

---

## 검증 완료 후 서비스 전환 (Nest 기준)

auth-lab 체크리스트가 전부 통과한 뒤에만:

1. `nest_app.dart`의 `LoginPage` → `LionAuthScreen` 교체 (별도 PR)
2. 소셜 첫 로그인 사용자의 실명 보완 화면 연결 (`session.metadata['real_name']` 부재 시)
3. `docs/architecture.md` 인증 섹션 갱신
4. 충분한 운영 검증 후 `login_page.dart` 제거
