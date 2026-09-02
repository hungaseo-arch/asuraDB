-- 2026-08-24 — 지표 수집 클라우드 이관 1/3: 인프라 (작업지시서 KPI지표_월별백필_2026 §7)
create extension if not exists pg_cron;
create extension if not exists pg_net;

grant usage on schema cron to postgres;

create table if not exists public.cron_run_log (
  id           bigint generated always as identity primary key,
  kind         text        not null,
  request_id   bigint,
  status       text        not null default 'requested',
  detail       text,
  requested_at timestamptz not null default now(),
  resolved_at  timestamptz
);

alter table public.cron_run_log enable row level security;

drop policy if exists "cron_run_log select" on public.cron_run_log;
create policy "cron_run_log select" on public.cron_run_log
  for select to authenticated using (true);

create or replace function public.trigger_collector(p_kind text)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text;
  v_key text;
  v_req bigint;
begin
  if p_kind not in ('fx', 'commodity', 'weekly', 'monthly') then
    raise exception 'trigger_collector: unknown kind %', p_kind;
  end if;

  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'service_role_key';

  if v_url is null or v_key is null or v_url like '%<%' or v_key like '%<%' then
    raise exception 'trigger_collector: vault secret project_url/service_role_key 미등록 (runbook 참고)';
  end if;

  v_req := net.http_post(
    url     := v_url || '/functions/v1/collect-indicators',
    headers := jsonb_build_object(
                 'Content-Type',  'application/json',
                 'Authorization', 'Bearer ' || v_key),
    body    := jsonb_build_object('kind', p_kind),
    timeout_milliseconds := 120000
  );

  insert into public.cron_run_log (kind, request_id) values (p_kind, v_req);
  return v_req;
end;
$$;

revoke all on function public.trigger_collector(text) from public, anon, authenticated;

create or replace function public.reap_cron_responses()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  update public.cron_run_log l
     set status      = case when r.status_code between 200 and 299 and r.error_msg is null
                            then 'ok' else 'error' end,
         detail      = left(coalesce(r.error_msg, r.content::text), 500),
         resolved_at = now()
    from net._http_response r
   where l.request_id = r.id
     and l.status = 'requested';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.reap_cron_responses() from public, anon, authenticated;
