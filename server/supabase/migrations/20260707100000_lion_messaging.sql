-- lion_auth 메시징 서브모듈 — 푸시 토큰 / 발송 로그 / 알림 설정
--
-- [모듈 템플릿] 이 파일이 원본이며, 각 서비스의 supabase/migrations/로 복사해
-- 적용한다(예: scripts/_apply_migration.mjs). 이식성을 위해 서비스별 스키마
-- (homeschool_id, term 등)에 의존하지 않는 generic 설계다. 특정 서비스의
-- 브로드캐스트 권한(예: Nest의 homeschool 역할)은 이 테이블에 컬럼을 추가하는
-- 대신 lion-notify Edge Function의 authorizeSend() 오버라이드에서 처리한다.
--
-- 저장 모델(3테이블):
--   push_tokens        : 사용자별 기기 푸시 토큰(FCM) — 클라이언트가 RLS 하에서 직접 등록
--   notification_log   : 발송 감사 로그 — Edge Function이 service_role로만 기록
--   notification_prefs : 사용자별 알림 수신 설정(푸시/알림톡 on-off, 방해금지 시간)

-- =====================================================
-- updated_at 트리거 헬퍼 (신규 프로젝트에서도 동작하도록 자체 제공; 멱등)
-- =====================================================
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- =====================================================
-- push_tokens — 기기 푸시 토큰 (본인만 CRUD)
-- =====================================================
create table if not exists public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null,
  platform text not null check (platform in ('android', 'ios', 'web')),
  device_id text,
  app_version text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  -- 로그아웃/토큰 폐기 시각. null 이면 활성 토큰.
  revoked_at timestamptz,
  constraint push_tokens_token_not_blank check (char_length(trim(token)) > 0),
  constraint push_tokens_user_token_unique unique (user_id, token)
);

create index if not exists idx_push_tokens_user
  on public.push_tokens(user_id);
-- 발송 시 활성 토큰만 조회하기 위한 부분 인덱스.
create index if not exists idx_push_tokens_active
  on public.push_tokens(user_id) where revoked_at is null;

drop trigger if exists trg_push_tokens_updated_at on public.push_tokens;
create trigger trg_push_tokens_updated_at
before update on public.push_tokens
for each row execute function public.set_updated_at();

-- =====================================================
-- notification_log — 발송 감사 로그 (service_role 기록, 본인 수신분만 조회)
-- =====================================================
create table if not exists public.notification_log (
  id uuid primary key default gen_random_uuid(),
  -- 발송을 요청한 사용자(Edge Function 호출자).
  requested_by uuid references auth.users(id) on delete set null,
  -- 수신 대상 사용자(발송 단위로 1행).
  to_user_id uuid references auth.users(id) on delete set null,
  -- 요청 채널: alimtalk | sms | push | auto
  channel text not null,
  -- 알림톡 템플릿 코드(해당 시).
  template_id text,
  -- accepted | failed | queued 등 프로바이더 응답 요약.
  status text not null default 'queued',
  -- 프로바이더가 돌려준 메시지 식별자(Solapi groupId/messageId, FCM name 등).
  provider_message_id text,
  -- 알림톡 실패 후 실제로 대체 발송된 채널(예: 'sms', 'lms'). null 이면 대체 없음.
  fallback_used text,
  error text,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_notification_log_to_user
  on public.notification_log(to_user_id);
create index if not exists idx_notification_log_requested_by
  on public.notification_log(requested_by);

-- =====================================================
-- notification_prefs — 사용자별 알림 수신 설정 (본인만)
-- =====================================================
create table if not exists public.notification_prefs (
  user_id uuid primary key references auth.users(id) on delete cascade,
  push_enabled boolean not null default true,
  alimtalk_enabled boolean not null default true,
  -- 방해금지(로컬 시간, 선택). start < end 가 아니어도 자정 넘김 허용을 위해 제약 없음.
  quiet_hours_start time,
  quiet_hours_end time,
  updated_at timestamptz not null default timezone('utc', now())
);

drop trigger if exists trg_notification_prefs_updated_at on public.notification_prefs;
create trigger trg_notification_prefs_updated_at
before update on public.notification_prefs
for each row execute function public.set_updated_at();

-- =====================================================
-- RLS
-- =====================================================
alter table public.push_tokens enable row level security;
alter table public.notification_log enable row level security;
alter table public.notification_prefs enable row level security;

-- ── push_tokens (본인 토큰만 CRUD) ──
drop policy if exists push_tokens_select_own on public.push_tokens;
create policy push_tokens_select_own on public.push_tokens
for select using (user_id = auth.uid());

drop policy if exists push_tokens_insert_own on public.push_tokens;
create policy push_tokens_insert_own on public.push_tokens
for insert with check (user_id = auth.uid());

drop policy if exists push_tokens_update_own on public.push_tokens;
create policy push_tokens_update_own on public.push_tokens
for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists push_tokens_delete_own on public.push_tokens;
create policy push_tokens_delete_own on public.push_tokens
for delete using (user_id = auth.uid());

-- ── notification_log (조회만: 본인이 받았거나 본인이 요청한 로그) ──
-- insert/update/delete 정책 없음 → 클라이언트 쓰기 차단.
-- Edge Function은 service_role(SUPABASE_SERVICE_ROLE_KEY)로 RLS를 우회해 기록한다.
drop policy if exists notification_log_select_own on public.notification_log;
create policy notification_log_select_own on public.notification_log
for select using (
  to_user_id = auth.uid() or requested_by = auth.uid()
);

-- ── notification_prefs (본인 설정만) ──
drop policy if exists notification_prefs_select_own on public.notification_prefs;
create policy notification_prefs_select_own on public.notification_prefs
for select using (user_id = auth.uid());

drop policy if exists notification_prefs_insert_own on public.notification_prefs;
create policy notification_prefs_insert_own on public.notification_prefs
for insert with check (user_id = auth.uid());

drop policy if exists notification_prefs_update_own on public.notification_prefs;
create policy notification_prefs_update_own on public.notification_prefs
for update using (user_id = auth.uid()) with check (user_id = auth.uid());
