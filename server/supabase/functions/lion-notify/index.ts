// lion_auth lion-notify — 통합 알림 발송(카카오 알림톡/SMS via Solapi + FCM 푸시).
//
// [모듈 템플릿] 이 파일이 원본이며, 각 서비스의 supabase/functions/lion-notify/로
// 복사해 배포한다. 이식성을 위해 _shared 없이 자체 완결로 작성되었다.
// 로그인된 사용자만 호출하므로 JWT 검증을 켠 채 배포한다(브로커와 반대).
//
// ⚠️ 복사 후 반드시 authorizeSend()를 서비스 정책에 맞게 조인다. 기본 정책은
//    "본인에게만 발송 가능"이다. 브로드캐스트(예: Nest의 STAFF/ADMIN가 반 전체
//    발송)를 열려면 여기서 역할을 검사하도록 오버라이드해야 한다. 그대로 두면
//    과도하게 열린 발송 함수가 되지 않는다(안전 기본값).
//
// 요청 계약 (POST, JSON):
//   { channel: 'auto'|'alimtalk'|'sms'|'push',
//     to_user_ids: string[],
//     template_id?: string, variables?: Record<string,string>,
//     title?: string, body?: string, data?: Record<string,string> }
//
// 응답: { accepted: bool, message_id?: string, fallback_used?: string }
//
// 필요 시크릿 (supabase secrets set 또는 setup 스크립트가 주입):
//   SOLAPI_API_KEY, SOLAPI_API_SECRET, SOLAPI_SENDER(발신번호), SOLAPI_PFID(발신프로필)
//   FCM_PROJECT_ID, FCM_SERVICE_ACCOUNT(서비스계정 JSON 또는 base64)
// 자동 주입: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";
import { JWT } from "npm:google-auth-library@9";

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

type Channel = "auto" | "alimtalk" | "sms" | "push";

interface NotifyRequest {
  channel: Channel;
  to_user_ids: string[];
  template_id?: string;
  variables?: Record<string, string>;
  title?: string;
  body?: string;
  data?: Record<string, string>;
}

// ─────────────────────────────────────────────── 인가 (서비스가 오버라이드)

/**
 * 발송 권한 검사. 기본 정책: 호출자는 자기 자신에게만 보낼 수 있다.
 *
 * 서비스별 확장 예(Nest): homeschool_memberships 에서 caller 의 역할이
 * HOMESCHOOL_ADMIN/STAFF 이면 to_user_ids 브로드캐스트 허용.
 */
async function authorizeSend(
  _admin: SupabaseClient,
  callerId: string,
  req: NotifyRequest,
): Promise<boolean> {
  return req.to_user_ids.every((id) => id === callerId);
}

// ─────────────────────────────────────────────── Solapi (알림톡 + SMS)

const encoder = new TextEncoder();

async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, encoder.encode(message));
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function solapiAuthHeader(): Promise<string> {
  const apiKey = Deno.env.get("SOLAPI_API_KEY") ?? "";
  const apiSecret = Deno.env.get("SOLAPI_API_SECRET") ?? "";
  const date = new Date().toISOString();
  const salt = crypto.randomUUID().replace(/-/g, "");
  const signature = await hmacSha256Hex(apiSecret, date + salt);
  return `HMAC-SHA256 apiKey=${apiKey}, date=${date}, salt=${salt}, signature=${signature}`;
}

interface SolapiMessage {
  to: string;
  from: string;
  text?: string;
  kakaoOptions?: {
    pfId: string;
    templateId?: string;
    variables?: Record<string, string>;
    disableSms?: boolean;
  };
}

/** Solapi send-many. { groupId, message_id } 요약을 반환한다. */
async function solapiSendMany(messages: SolapiMessage[]): Promise<{
  ok: boolean;
  messageId?: string;
  error?: string;
}> {
  const response = await fetch("https://api.solapi.com/messages/v4/send-many", {
    method: "POST",
    headers: {
      Authorization: await solapiAuthHeader(),
      "Content-Type": "application/json; charset=utf-8",
    },
    body: JSON.stringify({ messages }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    return {
      ok: false,
      error: data?.errorMessage ?? data?.message ?? `Solapi ${response.status}`,
    };
  }
  return { ok: true, messageId: data?.groupId ?? data?.groupInfo?.groupId };
}

function buildSolapiMessages(
  channel: Channel,
  from: string,
  pfId: string,
  recipients: { phone: string }[],
  req: NotifyRequest,
): SolapiMessage[] {
  const text = [req.title, req.body].filter(Boolean).join("\n");
  return recipients.map((r) => {
    if (channel === "sms") {
      return { to: r.phone, from, text };
    }
    // alimtalk / auto — disableSms=false 면 실패 시 SMS/LMS 자동 대체.
    return {
      to: r.phone,
      from,
      text: text || undefined,
      kakaoOptions: {
        pfId,
        templateId: req.template_id,
        variables: req.variables,
        disableSms: channel === "alimtalk", // alimtalk 전용 = 대체 없음
      },
    };
  });
}

// ─────────────────────────────────────────────── FCM (푸시)

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id?: string;
}

function parseServiceAccount(raw: string): ServiceAccount {
  try {
    return JSON.parse(raw);
  } catch {
    // base64 로 저장된 경우.
    return JSON.parse(atob(raw));
  }
}

let cachedFcmToken: { token: string; exp: number } | null = null;

async function fcmAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedFcmToken && cachedFcmToken.exp - 60 > now) {
    return cachedFcmToken.token;
  }
  const client = new JWT({
    email: sa.client_email,
    key: sa.private_key,
    scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
  });
  const { token } = await client.getAccessToken();
  if (!token) throw new Error("FCM 액세스 토큰 발급 실패");
  cachedFcmToken = { token, exp: now + 3300 };
  return token;
}

async function fcmSend(
  projectId: string,
  accessToken: string,
  token: string,
  platform: string,
  req: NotifyRequest,
): Promise<{ ok: boolean; name?: string; error?: string }> {
  const message: Record<string, unknown> = {
    token,
    notification: { title: req.title, body: req.body },
  };
  if (req.data && Object.keys(req.data).length > 0) message.data = req.data;
  if (platform === "android") message.android = { priority: "high" };
  if (platform === "ios") {
    message.apns = { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default" } } };
  }
  if (platform === "web") {
    message.webpush = { notification: { title: req.title, body: req.body } };
  }

  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ message }),
    },
  );
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    return { ok: false, error: data?.error?.message ?? `FCM ${response.status}` };
  }
  return { ok: true, name: data?.name };
}

// ─────────────────────────────────────────────── 핸들러

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "허용되지 않는 메서드입니다." });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  );

  // 1) 인증 — Bearer 토큰으로 호출자 확인.
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.replace(/^Bearer\s+/i, "");
  const { data: userData, error: userErr } = await admin.auth.getUser(bearer);
  if (userErr || !userData?.user) {
    return jsonResponse(401, { error: "로그인이 필요합니다." });
  }
  const callerId = userData.user.id;

  let body: NotifyRequest;
  try {
    body = (await req.json()) as NotifyRequest;
  } catch {
    return jsonResponse(400, { error: "요청 본문(JSON)이 올바르지 않습니다." });
  }

  const channel = body.channel;
  const toUserIds = Array.isArray(body.to_user_ids) ? body.to_user_ids : [];
  if (!channel || toUserIds.length === 0) {
    return jsonResponse(400, { error: "channel 과 to_user_ids 가 필요합니다." });
  }

  // 2) 인가.
  if (!(await authorizeSend(admin, callerId, body))) {
    return jsonResponse(403, { error: "이 대상에게 발송할 권한이 없습니다." });
  }

  try {
    if (channel === "push") {
      return await handlePush(admin, callerId, toUserIds, body);
    }
    return await handleKakaoOrSms(admin, callerId, channel, toUserIds, body);
  } catch (error) {
    console.error("[lion-notify] error:", error);
    const message =
      error instanceof Error ? error.message : "알림 발송에 실패했습니다.";
    return jsonResponse(500, { error: message });
  }
});

async function handlePush(
  admin: SupabaseClient,
  callerId: string,
  toUserIds: string[],
  req: NotifyRequest,
): Promise<Response> {
  const { data: tokens, error } = await admin
    .from("push_tokens")
    .select("user_id, token, platform")
    .in("user_id", toUserIds)
    .is("revoked_at", null);
  if (error) throw new Error(`push_tokens 조회 실패: ${error.message}`);
  if (!tokens || tokens.length === 0) {
    return jsonResponse(200, { accepted: false, error: "등록된 푸시 토큰이 없습니다." });
  }

  const sa = parseServiceAccount(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "");
  const projectId = Deno.env.get("FCM_PROJECT_ID") ?? sa.project_id ?? "";
  const accessToken = await fcmAccessToken(sa);

  const logs: Record<string, unknown>[] = [];
  let anyOk = false;
  let firstName: string | undefined;
  for (const t of tokens) {
    const result = await fcmSend(projectId, accessToken, t.token, t.platform, req);
    anyOk ||= result.ok;
    firstName ??= result.name;
    logs.push({
      requested_by: callerId,
      to_user_id: t.user_id,
      channel: "push",
      status: result.ok ? "accepted" : "failed",
      provider_message_id: result.name ?? null,
      error: result.error ?? null,
    });
  }
  await admin.from("notification_log").insert(logs);

  return jsonResponse(200, { accepted: anyOk, message_id: firstName ?? null });
}

async function handleKakaoOrSms(
  admin: SupabaseClient,
  callerId: string,
  channel: Channel,
  toUserIds: string[],
  req: NotifyRequest,
): Promise<Response> {
  // profiles.phone — 컬럼/테이블명은 서비스별로 다를 수 있다(여기 수정).
  const { data: profiles, error } = await admin
    .from("profiles")
    .select("id, phone")
    .in("id", toUserIds);
  if (error) throw new Error(`profiles 조회 실패: ${error.message}`);

  const recipients = (profiles ?? [])
    .filter((p) => typeof p.phone === "string" && p.phone.trim().length > 0)
    .map((p) => ({ userId: p.id as string, phone: (p.phone as string).replace(/-/g, "") }));
  if (recipients.length === 0) {
    return jsonResponse(200, { accepted: false, error: "발송할 전화번호가 없습니다." });
  }

  const from = Deno.env.get("SOLAPI_SENDER") ?? "";
  const pfId = Deno.env.get("SOLAPI_PFID") ?? "";
  const messages = buildSolapiMessages(channel, from, pfId, recipients, req);
  const result = await solapiSendMany(messages);

  const logs = recipients.map((r) => ({
    requested_by: callerId,
    to_user_id: r.userId,
    channel,
    template_id: req.template_id ?? null,
    status: result.ok ? "accepted" : "failed",
    provider_message_id: result.messageId ?? null,
    error: result.error ?? null,
  }));
  await admin.from("notification_log").insert(logs);

  if (!result.ok) {
    return jsonResponse(502, { error: `발송 실패: ${result.error}` });
  }
  return jsonResponse(200, { accepted: true, message_id: result.messageId ?? null });
}
