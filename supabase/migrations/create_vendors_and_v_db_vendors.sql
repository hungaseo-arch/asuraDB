-- 벤더(공급사) 마스터 + SAP A/P 브리지 뷰 (2026-08-06)
--
-- SAP A/P 에는 주소·연락처·결제조건·NPWP·은행정보가 없다. 따라서 vendors 는 수기 관리 항목을
-- 담는 마스터로 두고, 실적(매입액·수량·최종거래일)은 v_db_vendors 에서 SAP 를 롤업해 붙인다.
-- 금액 기준은 할인 반영액(disc_amount_idr), USD 는 IDR ÷ 문서환율로 뷰에서 계산(파생값 미저장).
--
-- 적용 순서: create_vendors_table → seed_vendors_from_sap → create_v_db_vendors

-- ── Phase 1. 스키마 ──────────────────────────────────────────────────────────
create table public.vendors (
  id               uuid primary key default gen_random_uuid(),
  vendor_code      text not null unique,
  vendor_name      text not null,
  sourcing         text not null default 'UNKNOWN'
                     check (sourcing in ('LOCAL','IMPORT','UNKNOWN')),
  country          text,
  vendor_type      text check (vendor_type in
                     ('MANUFACTURER','TRADER','AFFILIATE','SERVICE','OTHER')),
  npwp             text,
  address          text,
  contact_person   text,
  contact_phone    text,
  contact_email    text,
  payment_term     text,   -- TOP / Termin Pembayaran / 결제조건
  incoterms        text,   -- FOB, CIF, C&F, EXW
  settle_currency  text check (settle_currency in ('IDR','USD','CNY','KRW','INR')),
  bank_name        text,
  bank_account     text,
  pic_nik          text,   -- 자사 담당자 (staff.nik)
  pic_name         text,
  notes            text,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

comment on table public.vendors is
  '벤더(공급사) 마스터 — SAP A/P 미보유 항목(연락처·결제조건·NPWP 등) 수기 관리. 실적은 v_db_vendors에서 롤업.';

alter table public.vendors enable row level security;
create policy vendors_all_authenticated on public.vendors
  for all to authenticated using (true) with check (true);

-- updated_at 트리거는 기존 함수 재사용 (customers·products·staff 와 동일 규칙)
create trigger trg_vendors_updated_at before update on public.vendors
  for each row execute function set_updated_at();

-- sap_partners.customer_id 와 동일한 패턴으로 벤더 링크 추가
alter table public.sap_partners
  add column vendor_id uuid references public.vendors(id);
create index sap_partners_vendor_id_idx on public.sap_partners(vendor_id);

-- ── Phase 2. 시드 ───────────────────────────────────────────────────────────
-- vendor_code 는 최초 1회 매입액(USD) 내림차순으로 V001~V027 고정 부여한다.
-- 이후 실적이 바뀌어도 재부여하지 않는다(외부 참조 안정성).
-- 국가는 사명으로 판별 가능한 것만 채우고, 불명확하면 NULL 로 두어 UI 에서 「미확인」으로 드러낸다.
with rank_src as (
  select h.partner_id,
         sum(l.disc_amount_idr / nullif(h.ex_rate, 0))
           filter (where h.status = 'INV') as usd
  from sap_purchase_invoices h
  join sap_purchase_invoice_lines l using (doc_no)
  group by h.partner_id
),
src as (
  select p.id as partner_id, p.name,
         row_number() over (order by coalesce(r.usd, 0) desc, p.name) as rn
  from sap_partners p
  left join rank_src r on r.partner_id = p.id
  where p.is_supplier
),
ins as (
  insert into public.vendors (vendor_code, vendor_name, sourcing, country)
  select 'V' || lpad(rn::text, 3, '0'),
         name,
         case
           when name ~* '^(PT\.|PT |CV\.|CV )' then 'LOCAL'
           when name ~* 'INDONESIA'            then 'LOCAL'
           else 'IMPORT'
         end,
         case
           when name ~* '^(PT\.|PT |CV\.|CV )' or name ~* 'INDONESIA' then 'Indonesia'
           when name ~* '(HUBEI|SHANXI|DONGYING|QINGDAO|SHANGHAI|TECHKING TIRES LIMITED)' then 'China'
           when name ~* 'JK TYRE' then 'India'
           else null                              -- 미확인 → NULL, 수기 확인 대상
         end
  from src
  returning id, vendor_name
)
update public.sap_partners p
set vendor_id = i.id
from ins i
where p.name = i.vendor_name and p.is_supplier;

-- ── Phase 3. 브리지 뷰 ──────────────────────────────────────────────────────
create or replace view public.v_db_vendors
with (security_invoker = true) as
with agg as (
  select h.partner_id,
    count(distinct h.doc_no) filter (where h.status = 'INV')            as ap_invoice_cnt,
    count(*)                 filter (where h.status = 'INV')            as ap_line_cnt,
    sum(l.qty)               filter (where h.status = 'INV')            as qty_total,
    sum(l.disc_amount_idr)   filter (where h.status = 'INV')            as purchase_idr,
    sum(l.disc_amount_idr / nullif(h.ex_rate, 0))
                             filter (where h.status = 'INV')            as purchase_usd,
    min(h.inv_date)          filter (where h.status = 'INV')            as first_inv_date,
    max(h.inv_date)          filter (where h.status = 'INV')            as last_inv_date,
    count(*)                 filter (where h.status = 'INV_CXL')        as cxl_line_cnt,
    abs(sum(l.disc_amount_idr / nullif(h.ex_rate, 0))
                             filter (where h.status = 'INV_CXL'))       as cxl_usd
  from sap_purchase_invoices h
  join sap_purchase_invoice_lines l using (doc_no)
  group by h.partner_id
),
mix as (
  select h.partner_id,
    mode() within group (order by i.brand) filter (where i.brand is not null) as top_brand,
    mode() within group (order by i.type0) filter (where i.type0 is not null) as top_category
  from sap_purchase_invoices h
  join sap_purchase_invoice_lines l using (doc_no)
  left join sap_items i on i.sku = l.sku
  where h.status = 'INV'
  group by h.partner_id
)
select
  v.id, v.vendor_code, v.vendor_name, v.sourcing, v.country, v.vendor_type,
  v.payment_term, v.incoterms, v.settle_currency,
  v.contact_person, v.contact_phone, v.contact_email, v.npwp, v.pic_name,
  v.is_active,
  p.id as sap_partner_id,
  coalesce(a.ap_invoice_cnt, 0)              as ap_invoice_cnt,
  coalesce(a.ap_line_cnt, 0)                 as ap_line_cnt,
  coalesce(a.qty_total, 0)                   as qty_total,
  round(coalesce(a.purchase_idr, 0), 0)      as purchase_idr,
  round(coalesce(a.purchase_usd, 0), 2)      as purchase_usd,
  round(100 * coalesce(a.purchase_usd, 0)
        / nullif(sum(a.purchase_usd) over (), 0), 1) as share_pct,
  a.first_inv_date,
  a.last_inv_date,
  case when a.last_inv_date is null then null
       else (date_part('year',  age(current_date, a.last_inv_date)) * 12
           + date_part('month', age(current_date, a.last_inv_date)))::int
  end as months_since_last,
  coalesce(a.cxl_line_cnt, 0)                as cxl_line_cnt,
  round(coalesce(a.cxl_usd, 0), 2)           as cxl_usd,
  m.top_brand,
  m.top_category
from public.vendors v
left join public.sap_partners p on p.vendor_id = v.id
left join agg a on a.partner_id = p.id
left join mix m on m.partner_id = p.id;

comment on view public.v_db_vendors is
  'vendors + SAP A/P 롤업 (status=INV 기준, 금액=disc_amount_idr, USD=IDR/ex_rate). Databases.vue 벤더탭 조회용.';
