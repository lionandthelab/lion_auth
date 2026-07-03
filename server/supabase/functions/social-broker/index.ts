// lion_auth social-broker — Supabase 미지원 프로바이더(Naver) 세션 중개.
//
// [모듈 템플릿] 이 파일이 원본이며, 각 서비스의 supabase/functions/social-broker/로
// 복사해 배포한다. 이식성을 위해 _shared 없이 자체 완결로 작성되었다.
//
// 플로우:
//   1. 클라이언트가 {provider:'naver', access_token} (앱) 또는
//      {provider:'naver', auth_code, state, redirect_uri} (웹)를 보낸다.
//   2. auth_code면 네이버 토큰 엔드포인트에서 access_token으로 교환한다.
//      (client_secret은 이 함수의 시크릿으로만 보관 — 웹 클라이언트에 노출 금지)
//   3. 네이버 프로필 API로 토큰을 검증하고 이메일/이름을 얻는다.
//   4. service_role로 사용자를 upsert하고 magiclink token_hash를 발급한다.
//   5. 클라이언트는 verifyOtp(token_hash)로 정식 Supabase 세션을 만든다.
//
// 필요 시크릿 (supabase secrets set 또는 setup 스크립트가 주입):
//   NAVER_CLIENT_ID, NAVER_CLIENT_SECRET
// 자동 주입: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

interface NaverProfile {
  id: string;
  email?: string;
  name?: string;
  nickname?: string;
  profile_image?: string;
}

async function exchangeNaverCode(
  code: string,
  state: string,
): Promise<string> {
  const params = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: Deno.env.get("NAVER_CLIENT_ID") ?? "",
    client_secret: Deno.env.get("NAVER_CLIENT_SECRET") ?? "",
    code,
    state,
  });
  const response = await fetch(
    `https://nid.naver.com/oauth2.0/token?${params}`,
  );
  const data = await response.json();
  if (!data.access_token) {
    throw new Error(
      `네이버 토큰 교환에 실패했습니다. (${data.error_description ?? data.error ?? "unknown"})`,
    );
  }
  return data.access_token as string;
}

async function fetchNaverProfile(accessToken: string): Promise<NaverProfile> {
  const response = await fetch("https://openapi.naver.com/v1/nid/me", {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  const data = await response.json();
  if (data.resultcode !== "00" || !data.response?.id) {
    throw new Error("네이버 프로필 조회에 실패했습니다. 토큰이 유효하지 않습니다.");
  }
  return data.response as NaverProfile;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "허용되지 않는 메서드입니다." });
  }

  try {
    const body = await req.json();
    if (body.provider !== "naver") {
      return jsonResponse(400, {
        error: `지원하지 않는 프로바이더입니다: ${body.provider}`,
      });
    }

    // 1) access_token 확보 (웹: 인가 코드 교환 / 앱: 그대로 사용)
    let accessToken: string | undefined = body.access_token;
    if (!accessToken && body.auth_code) {
      accessToken = await exchangeNaverCode(body.auth_code, body.state ?? "");
    }
    if (!accessToken) {
      return jsonResponse(400, { error: "access_token 또는 auth_code가 필요합니다." });
    }

    // 2) 토큰 검증 + 프로필 조회
    const profile = await fetchNaverProfile(accessToken);
    const email = profile.email?.trim().toLowerCase();
    if (!email) {
      return jsonResponse(400, {
        error:
          "네이버 계정에서 이메일 제공에 동의해 주세요. " +
          "(네이버 개발자 콘솔의 이메일 필수 동의 설정도 확인 필요)",
      });
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    );

    // 3) 사용자 upsert (이메일 기준 — 기존 이메일 가입자는 같은 계정으로 연결)
    let isNewUser = false;
    const displayName = profile.name ?? profile.nickname ?? "";
    const { error: createError } = await admin.auth.admin.createUser({
      email,
      email_confirm: true,
      user_metadata: {
        full_name: displayName,
        avatar_url: profile.profile_image ?? null,
      },
      app_metadata: {
        provider: "naver",
        providers: ["naver"],
        naver_id: profile.id,
      },
    });
    if (!createError) {
      isNewUser = true;
    } else if (createError.code !== "email_exists") {
      console.error("[social-broker] createUser failed:", createError);
      return jsonResponse(500, { error: "계정 생성에 실패했습니다." });
    }

    // 4) magiclink token_hash 발급 → 클라이언트가 verifyOtp로 세션 생성
    const { data: linkData, error: linkError } =
      await admin.auth.admin.generateLink({ type: "magiclink", email });
    if (linkError || !linkData?.properties?.hashed_token) {
      console.error("[social-broker] generateLink failed:", linkError);
      return jsonResponse(500, { error: "로그인 토큰 발급에 실패했습니다." });
    }

    return jsonResponse(200, {
      token_hash: linkData.properties.hashed_token,
      email,
      is_new_user: isNewUser,
    });
  } catch (error) {
    console.error("[social-broker] error:", error);
    const message =
      error instanceof Error ? error.message : "소셜 로그인 처리에 실패했습니다.";
    return jsonResponse(500, { error: message });
  }
});
