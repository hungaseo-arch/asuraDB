-- 2026-10-13 — 레거시 JWT 비밀값 폐기 대비: pg_cron → Edge Function 호출 인증을 신규 secret key 로 전환
--
-- 기존: vault 'service_role_key'(레거시 service_role JWT) 를 Authorization: Bearer 로 전송 → verify_jwt 통과.
--       레거시 JWT 비밀값을 폐기하면 이 JWT 는 무효가 되어 수집·셀피정리 cron 이 401 로 실패한다.
-- 변경: vault 'secret_key'(sb_secret_…) 를 apikey 헤더로 전송. 함수는 verify_jwt=false 로 배포하고
--       apikey 가 SUPABASE_SECRET_KEYS 중 하나인지 직접 검증한다(collect-indicators, attendance-selfie-cleanup).
--       신규 키는 JWT 가 아니므로 Authorization 헤더에 넣으면 안 된다(Supabase 문서).
--
-- 선행(대시보드 SQL Editor, 값은 저장소에 두지 않는다):
--   select vault.create_secret('<sb_secret_… 값>', 'secret_key', 'pg_cron → Edge Function apikey');

create or replace function public.trigger_collector(p_kind text)
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_url text;
  v_key text;
  v_req bigint;
begin
  if p_kind not in ('fx', 'commodity', 'weekly', 'monthly') then
    raise exception 'trigger_collector: unknown kind %', p_kind;
  end if;

  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'secret_key';

  if v_url is null or v_key is null or v_url like '%<%' or v_key like '%<%' then
    raise exception 'trigger_collector: vault secret project_url/secret_key 미등록 (runbook 참고)';
  end if;

  v_req := net.http_post(
    url     := v_url || '/functions/v1/collect-indicators',
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'apikey',       v_key),
    body    := jsonb_build_object('kind', p_kind),
    timeout_milliseconds := 120000
  );

  insert into public.cron_run_log (kind, request_id) values (p_kind, v_req);
  return v_req;
end;
$function$;

create or replace function public.trigger_attendance_selfie_cleanup()
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_url text;
  v_key text;
  v_req bigint;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'secret_key';

  if v_url is null or v_key is null or v_url like '%<%' or v_key like '%<%' then
    raise exception 'trigger_attendance_selfie_cleanup: vault secret project_url/secret_key 미등록';
  end if;

  v_req := net.http_post(
    url     := v_url || '/functions/v1/attendance-selfie-cleanup',
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'apikey',       v_key),
    body    := '{}'::jsonb,
    timeout_milliseconds := 60000
  );

  insert into public.cron_run_log (kind, request_id) values ('attendance_selfie_cleanup', v_req);
  return v_req;
end;
$function$;

-- 레거시 JWT 비밀값 폐기 후 더 이상 쓰지 않는 vault 항목 정리(폐기·검증 완료 뒤 실행):
--   delete from vault.secrets where name = 'service_role_key';
