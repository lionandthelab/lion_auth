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
| 프로덕션 웹(앱) | `https://nestapp.life/` (origin: `https://nestapp.life`) |
| **홈페이지(공개 소개) URL** | `https://nestapp.life/welcome.html` |
| 개인정보처리방침 URL | `https://nestapp.life/privacy.html` |
| 이용약관 URL | `https://nestapp.life/terms.html` |

> **OAuth 콘솔의 "애플리케이션 홈페이지"에는 반드시 `welcome.html`(공개 소개
> 페이지)을 등록한다.** 루트 `/`는 Flutter 앱이 로그인 화면으로 부팅되므로,
> Google OAuth 심사의 "홈페이지가 로그인 뒤에 있음 / 앱 목적 미설명" 지적을
> 받는다. `welcome.html`은 로그인 없이 앱 목적을 설명하는 정적 페이지다.
>
> 개인정보처리방침·이용약관 페이지는 `frontend/assets/legal/*.md`(단일 소스)에서
> 관리하며, `node scripts/render_legal.mjs`가 정적 HTML을 생성한다.
> `welcome.html`은 `frontend/web/welcome.html`에 직접 관리한다.

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
   - 애플리케이션 홈페이지: https://nestapp.life/welcome.html  ← 루트(/) 아님! (로그인 벽·목적 미설명으로 심사 반려됨)
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

### 1-E. Solapi (카카오 알림톡 + SMS) — 브라우저 에이전트 프롬프트

```text
Solapi(https://solapi.com)에 가입/로그인해서 다음 작업을 수행해줘.

1. [발송준비 > 발신번호] 새 발신번호 등록 → 휴대폰/ARS 인증 완료
   (알림톡 실패 시 SMS/LMS 자동 대체, 그리고 SMS 직접 발송에 쓰인다)

2. [카카오채널] 카카오 비즈니스 채널 연동
   - 카카오톡 채널이 없으면 카카오 비즈니스(https://business.kakao.com)에서 채널을 먼저 생성
   - Solapi에서 채널 연동(연동 토큰 신청 → 카카오에서 받은 토큰 입력)
   - 연동 완료 후 발신프로필 ID(PF...로 시작)를 확인

3. [알림톡 > 템플릿] 최소 1개 템플릿 등록 후 검수 요청
   - 본문의 치환 변수는 #{변수명} 형식 사용 (예: #{이름}님, 안녕하세요)
   - 카카오 검수 승인 후 템플릿 코드(KA...로 시작)가 발급됨

4. [설정 > API Key] API Key/Secret 발급 후 결과를 아래 형식으로 출력:

SOLAPI_API_KEY=<API Key>
SOLAPI_API_SECRET=<API Secret>
SOLAPI_SENDER=<등록한 발신번호, 숫자만 예: 0212345678>
SOLAPI_PFID=<발신프로필 ID(PF...)>
```

> **알림톡 템플릿 승인은 카카오 검수 게이트다**(영업일 소요). 승인 전에도
> `SOLAPI_SENDER`만 있으면 `channel:"sms"` 직접 발송과 `channel:"auto"`의 SMS
> 대체 발송으로 파이프라인을 검증할 수 있다. 실제 알림톡 전달은 템플릿 승인 후 가능.

### 1-F. Firebase / FCM (푸시) — 브라우저 에이전트 프롬프트

```text
Firebase 콘솔(https://console.firebase.google.com)에서 다음 작업을 수행해줘.

1. 프로젝트 생성(또는 기존 재사용): 이름 "nest-lionandthelab"

2. 앱 3개 등록:
   - Android: 패키지 com.lionandthelab.nest → google-services.json 다운로드
     (frontend/android/app/ 에 배치)
   - iOS: 번들 ID com.lionandthelab.nest → GoogleService-Info.plist 다운로드
     (frontend/ios/Runner/ 에 배치, Xcode Runner 타깃에 추가)
   - 웹 앱 등록 → firebaseConfig(apiKey/appId/messagingSenderId 등) 확보

3. [프로젝트 설정 > Cloud Messaging]
   - iOS: APNs 인증 키(.p8) 업로드 (Apple Developer > Keys 에서 발급)
   - 웹 푸시 인증서(Web Push certificates)에서 키 쌍 생성 → 공개 VAPID 키 확보

4. [프로젝트 설정 > 서비스 계정] 새 비공개 키 생성 → 서비스계정 JSON 다운로드
   (이 JSON은 서버 시크릿 — 절대 클라이언트/깃에 넣지 말 것)

5. 결과를 아래 형식으로 출력:

FCM_PROJECT_ID=<Firebase 프로젝트 ID>
LION_FCM_WEB_VAPID_KEY=<웹 푸시 공개 VAPID 키>
```

> **호스트 자산(모듈이 대신 넣어줄 수 없는 파일):**
> `google-services.json`, `GoogleService-Info.plist`, 그리고 웹의
> `frontend/web/firebase-messaging-sw.js`(앱 senderId 포함 서비스워커). 셋업
> 스크립트가 자동 패치하지 않으므로 위 안내대로 직접 배치한다. 또한 호스트 앱에서
> `flutterfire configure`를 실행해 `firebase_options.dart`를 생성하고, `main()`에서
> `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`를 부른다.
>
> `FCM_SERVICE_ACCOUNT`는 다운로드한 서비스계정 JSON을 **한 줄**로 넣거나
> base64로 인코딩해 넣는다(둘 다 지원). `.env`는 gitignore 되어 커밋되지 않는다.

---

## 2단계 — .env 채우기

브라우저 에이전트가 출력한 값들을 `.env`에 붙여넣는다. 스키마 전체는
[`.env.example`](.env.example) 참고.

> **위치**: `LION_*` 키는 `packages/lion_auth/.env`(이 폴더) 또는 저장소 루트
> `.env` 어느 쪽에 넣어도 된다 — setup/run 스크립트가 두 파일을 병합해서 읽고
> 패키지 쪽 값을 우선한다. 두 파일 모두 gitignore 되어 커밋되지 않는다.

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

# --- 메시징(알림톡·푸시) ---
node scripts/lion_auth_setup.mjs messaging          # 아래 3개 + doctor
node scripts/lion_auth_setup.mjs migrate-messaging  # push_tokens/notification_log/notification_prefs 마이그레이션
node scripts/lion_auth_setup.mjs messaging-secrets  # Solapi/FCM 시크릿 주입 (Management API)
node scripts/lion_auth_setup.mjs notify             # lion-notify Edge Function 배포 (JWT 검증 ON)
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

## 5단계 — 메시징(알림톡·푸시) 독립 검증

> **철칙(로그인과 동일): messaging-lab에서 검증되기 전에는 실제 앱의 알림 트리거에
> 연결하지 않는다.** 아래 랩은 기존 로그인/앱 동작을 전혀 건드리지 않는 독립 타깃이다.

```powershell
# 웹 (Chrome) — 알림 권한 팝업 허용 필요
node scripts/run_messaging_lab.mjs

# Android 에뮬레이터 (Google Play 탑재 이미지 권장 — FCM 수신 가능)
node scripts/run_messaging_lab.mjs -d emulator-5554

# 헤드리스 스모크 (푸시 토큰 등록/DB행/함수 accept 확인)
node scripts/messaging_lab_smoke.mjs
```

콘솔 승인 없이 검증 가능:

- [ ] 웹/에뮬: 로그인 → "권한 요청" → "토큰 등록" → `push_tokens` 행 생성
- [ ] "나에게 테스트 푸시"(`channel:"push"`) → 포그라운드 메시지 수신 + `notification_log` 행
- [ ] `SOLAPI_SENDER`만 있으면 `channel:"sms"` → 운영자 폰으로 실제 SMS 1건
- [ ] 로그아웃 → `push_tokens.revoked_at` 세팅

운영자 콘솔 승인 후에만(수동 최종 확인):

- [ ] 실제 알림톡 전달 (승인 템플릿 + 발신번호 + 카카오 채널)
- [ ] iOS 실기기 푸시 (APNs 키 + 기기)

---

## HttpLionMessagingBackend 서버 계약 (비-Supabase 서비스용)

Supabase가 아닌 서비스는 아래 계약의 서버를 구현하고 `HttpLionMessagingBackend`를 쓴다.
호출자 식별은 `Authorization: Bearer <token>`(로그인 세션)로 한다.

| 엔드포인트 | 요청 | 성공 응답 |
|---|---|---|
| `POST /messaging/register-token` | `{token, platform, device_id?, app_version?}` | `{}` |
| `POST /messaging/unregister-token` | `{token}` | `{}` |
| `POST /messaging/send` | `{channel, to_user_ids, template_id?, variables?, title?, body?, data?}` | `{accepted, message_id?, fallback_used?}` |

실패 응답은 공통으로 `{"error": "<한국어 메시지>"}`. 서버는 발송 시 Solapi API Key/Secret,
FCM 서비스계정을 **자체 보관**하며 클라이언트에 노출하지 않는다(Supabase 어댑터의
`lion-notify` Edge Function과 동일한 역할).

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
| 웹 푸시 토큰이 null | `LION_FCM_WEB_VAPID_KEY` 미주입 또는 `web/firebase-messaging-sw.js` 서비스워커 누락 |
| iOS 푸시 무음 | APNs 인증 키(.p8) Firebase 미업로드 / Xcode Push Notifications·Background Modes 미설정 (시뮬레이터는 원격 푸시 미지원) |
| 알림톡 대신 SMS로 감 | 템플릿 미승인 또는 `templateId`·`#{변수}` 불일치 → `disableSms=false`라 SMS 대체된 것(정상 동작) |
| Solapi `발신번호 미등록` | `SOLAPI_SENDER` 미인증 — 콘솔 발신번호 인증 완료 필요 |
| lion-notify `401 로그인이 필요합니다` | 함수가 JWT 검증 ON으로 배포됨 — 로그인 세션의 Bearer 토큰으로 호출해야 함(정상) |
| lion-notify `403 발송 권한 없음` | `authorizeSend` 기본 정책(본인만) — 브로드캐스트는 함수 복사본에서 역할 검사로 오버라이드 |

---

## 검증 완료 후 서비스 전환 (Nest 기준)

auth-lab 체크리스트가 전부 통과한 뒤에만:

1. `nest_app.dart`의 `LoginPage` → `LionAuthScreen` 교체 (별도 PR)
2. 소셜 첫 로그인 사용자의 실명 보완 화면 연결 (`session.metadata['real_name']` 부재 시)
3. `docs/architecture.md` 인증 섹션 갱신
4. 충분한 운영 검증 후 `login_page.dart` 제거
