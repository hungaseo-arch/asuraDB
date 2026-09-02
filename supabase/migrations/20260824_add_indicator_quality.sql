alter table public.indicator_history
  add column if not exists quality text
    check (quality in ('실측','파생','추정'));

comment on column public.indicator_history.quality is
  '실측=1차 공식 소스 원본값 / 파생=보유 데이터에서 규칙으로 산출 / 추정=대용지표·프록시';

create index if not exists indicator_history_quality_idx
  on public.indicator_history (indicator_id, quality);

update public.indicator_history set quality = '추정'
 where quality is null
   and (note ilike '%Proxy%' or note ilike '%추정%' or note ilike '%근사치%');

update public.indicator_history set quality = '파생'
 where quality is null and (note ilike '%derived%' or note ilike '%단위환산%');

update public.indicator_history set quality = '실측'
 where quality is null;
