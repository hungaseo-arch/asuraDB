-- 회사 DB · 구매 현황 / 판매 현황 집계 뷰 (2026-08-07)
--
-- Databases.vue 의 신규 탭 2개(구매 현황·판매 현황)에서 기간별·거래처별·아이템별·SKU별 조회에 쓴다.
-- 소스는 SAP 거래이력(A/R 판매 · A/P 구매). 월 × 축 단위로만 집계해 두고, 기간 필터와
-- 아이템 롤업(=SKU 뷰의 item 컬럼 기준)은 화면에서 처리한다.
--
-- 집계 기준
--   · 금액은 할인 후 금액(disc_amount_idr) — 마진·브리지 뷰와 동일 기준.
--   · 취소·크레딧메모(INV_CXL·CM·CM_CXL)의 수량·금액은 원본에 이미 음수로 들어 있으므로
--     전 status 를 합산해 순(net) 값을 낸다. (status 를 걸러내면 취소분이 빠져 과대 계상됨)
--   · USD 는 IDR ÷ 문서환율. 환율이 없는 문서(크레딧메모 일부)는 USD 집계에서 제외된다.
--   · 아이템(item) = sap_items.type0 — 'TIRE (TBR)' 처럼 제품+유형이 합쳐진 23종 분류.

-- ── 판매(A/R) ────────────────────────────────────────────────────────────────
create or replace view public.v_db_sales_monthly
with (security_invoker = true) as
select
  to_char(h.inv_date, 'YYYY-MM')                       as year_month,
  count(distinct h.doc_no)                             as doc_cnt,
  count(distinct h.partner_id)                         as partner_cnt,
  sum(l.qty)                                           as qty,
  sum(l.disc_amount_idr)                               as amount_idr,
  sum(l.disc_amount_idr / nullif(h.ex_rate, 0))        as amount_usd
from public.sap_sales_invoices h
join public.sap_sales_invoice_lines l using (doc_no)
where h.inv_date is not null
group by 1;

create or replace view public.v_db_sales_by_customer
with (security_invoker = true) as
select
  to_char(h.inv_date, 'YYYY-MM')                       as year_month,
  h.partner_id,
  p.name                                               as partner_name,
  c.customer_code,
  count(distinct h.doc_no)                             as doc_cnt,
  sum(l.qty)                                           as qty,
  sum(l.disc_amount_idr)                               as amount_idr,
  sum(l.disc_amount_idr / nullif(h.ex_rate, 0))        as amount_usd
from public.sap_sales_invoices h
join public.sap_sales_invoice_lines l using (doc_no)
join public.sap_partners p on p.id = h.partner_id
left join public.customers c on c.id = p.customer_id
where h.inv_date is not null
group by 1, 2, 3, 4;

create or replace view public.v_db_sales_by_sku
with (security_invoker = true) as
select
  to_char(h.inv_date, 'YYYY-MM')                       as year_month,
  l.sku,
  i.description,
  i.brand,
  i.type0                                              as item,
  count(distinct h.doc_no)                             as doc_cnt,
  sum(l.qty)                                           as qty,
  sum(l.disc_amount_idr)                               as amount_idr,
  sum(l.disc_amount_idr / nullif(h.ex_rate, 0))        as amount_usd
from public.sap_sales_invoices h
join public.sap_sales_invoice_lines l using (doc_no)
left join public.sap_items i on i.sku = l.sku
where h.inv_date is not null and l.sku is not null
group by 1, 2, 3, 4, 5;

-- ── 구매(A/P) ────────────────────────────────────────────────────────────────
create or replace view public.v_db_purchases_monthly
with (security_invoker = true) as
select
  to_char(h.inv_date, 'YYYY-MM')                       as year_month,
  count(distinct h.doc_no)                             as doc_cnt,
  count(distinct h.partner_id)                         as partner_cnt,
  sum(l.qty)                                           as qty,
  sum(l.disc_amount_idr)                               as amount_idr,
  sum(l.disc_amount_idr / nullif(h.ex_rate, 0))        as amount_usd
from public.sap_purchase_invoices h
join public.sap_purchase_invoice_lines l using (doc_no)
where h.inv_date is not null
group by 1;

create or replace view public.v_db_purchases_by_vendor
with (security_invoker = true) as
select
  to_char(h.inv_date, 'YYYY-MM')                       as year_month,
  h.partner_id,
  p.name                                               as partner_name,
  v.vendor_code,
  count(distinct h.doc_no)                             as doc_cnt,
  sum(l.qty)                                           as qty,
  sum(l.disc_amount_idr)                               as amount_idr,
  sum(l.disc_amount_idr / nullif(h.ex_rate, 0))        as amount_usd
from public.sap_purchase_invoices h
join public.sap_purchase_invoice_lines l using (doc_no)
join public.sap_partners p on p.id = h.partner_id
left join public.vendors v on v.id = p.vendor_id
where h.inv_date is not null
group by 1, 2, 3, 4;

create or replace view public.v_db_purchases_by_sku
with (security_invoker = true) as
select
  to_char(h.inv_date, 'YYYY-MM')                       as year_month,
  l.sku,
  i.description,
  i.brand,
  i.type0                                              as item,
  count(distinct h.doc_no)                             as doc_cnt,
  sum(l.qty)                                           as qty,
  sum(l.disc_amount_idr)                               as amount_idr,
  sum(l.disc_amount_idr / nullif(h.ex_rate, 0))        as amount_usd
from public.sap_purchase_invoices h
join public.sap_purchase_invoice_lines l using (doc_no)
left join public.sap_items i on i.sku = l.sku
where h.inv_date is not null and l.sku is not null
group by 1, 2, 3, 4, 5;

comment on view public.v_db_sales_monthly     is '판매(A/R) 월별 집계 — Databases.vue 판매 현황 탭.';
comment on view public.v_db_sales_by_customer is '판매(A/R) 월×고객 집계 — Databases.vue 판매 현황 탭.';
comment on view public.v_db_sales_by_sku      is '판매(A/R) 월×SKU 집계(item=type0) — Databases.vue 판매 현황 탭. 아이템별은 이 뷰를 item 기준으로 롤업.';
comment on view public.v_db_purchases_monthly    is '구매(A/P) 월별 집계 — Databases.vue 구매 현황 탭.';
comment on view public.v_db_purchases_by_vendor  is '구매(A/P) 월×벤더 집계 — Databases.vue 구매 현황 탭.';
comment on view public.v_db_purchases_by_sku     is '구매(A/P) 월×SKU 집계(item=type0) — Databases.vue 구매 현황 탭.';

-- ── 보정(2026-08-07) — SKU 뷰에 품목코드 없는 라인 포함 ─────────────────────
-- 운임 등 Item Code 가 비어 있는 라인(판매 91 · 구매 558행)을 제외하면 SKU/아이템 축 합계가
-- 기간·거래처 축과 어긋난다(구매 기준 22,128,805,990 IDR · 1.3%). 버리지 않고 '(품목코드 없음)'
-- / item='ETC (기타)' 로 드러낸다. → 네 축 합계가 모두 원장과 일치.
create or replace view public.v_db_sales_by_sku
with (security_invoker = true) as
select
  to_char(h.inv_date, 'YYYY-MM')                       as year_month,
  coalesce(l.sku, '(품목코드 없음)')                    as sku,
  coalesce(i.description, '운임·기타')                  as description,
  i.brand,
  coalesce(i.type0, 'ETC (기타)')                       as item,
  count(distinct h.doc_no)                             as doc_cnt,
  sum(l.qty)                                           as qty,
  sum(l.disc_amount_idr)                               as amount_idr,
  sum(l.disc_amount_idr / nullif(h.ex_rate, 0))        as amount_usd
from public.sap_sales_invoices h
join public.sap_sales_invoice_lines l using (doc_no)
left join public.sap_items i on i.sku = l.sku
where h.inv_date is not null
group by 1, 2, 3, 4, 5;

create or replace view public.v_db_purchases_by_sku
with (security_invoker = true) as
select
  to_char(h.inv_date, 'YYYY-MM')                       as year_month,
  coalesce(l.sku, '(품목코드 없음)')                    as sku,
  coalesce(i.description, '운임·기타')                  as description,
  i.brand,
  coalesce(i.type0, 'ETC (기타)')                       as item,
  count(distinct h.doc_no)                             as doc_cnt,
  sum(l.qty)                                           as qty,
  sum(l.disc_amount_idr)                               as amount_idr,
  sum(l.disc_amount_idr / nullif(h.ex_rate, 0))        as amount_usd
from public.sap_purchase_invoices h
join public.sap_purchase_invoice_lines l using (doc_no)
left join public.sap_items i on i.sku = l.sku
where h.inv_date is not null
group by 1, 2, 3, 4, 5;
