-- 마진 명세(margin_lines) — 월간 sales analysis report 의 「1.Row_Data」 시트 (2026-08-06)
--
-- 기존 margin_records 는 4개 축(brand/product/customer/item)을 각각 따로 집계한 요약이라
-- 축을 교차한 조회(고객 × SKU 등)가 원천적으로 불가능했다. 엑셀 원본에는 PDF 에 없는
-- 거래 명세 시트가 있어, 이를 라인 단위로 적재해 임의 조합 필터를 가능하게 한다.
--
-- 원본 성격: SAP 배송(delivery) 기준 + 원가/마진 컬럼. doc_no 는 sap_deliveries.doc_no 와 같은 체계다
-- (2026-07 대조: 배송 doc 44902~45534 의 수량 61,871 = 마진 리포트 수량과 일치).
--
-- 파생값 미저장 원칙:
--   금액   = qty × unit_price_idr      (원본 Amount(IDR))
--   원가   = qty × unit_cost_idr       (원본 P_Amount(IDR))
--   마진   = sales_idr − 원가          (원본 Margin(IDR))
-- 62,583행 전수 검사에서 위 관계가 부동소수점 오차(≤5e-7) 내로 정확히 성립함을 확인하고
-- 원본 열(qty·단가·원가단가·할인후매출)만 저장한다. 계산은 v_margin_lines 에서 한다.
-- sales_idr(할인 후 매출)은 단가로 역산할 수 없어 원본 그대로 보관한다.

create table public.margin_lines (
  id              bigint generated always as identity primary key,
  year_month      text     not null,
  doc_no          integer  not null,               -- SAP Doc. No. (= sap_deliveries.doc_no 체계)
  partner_id      smallint not null references public.sap_partners(id),
  sku             text     not null references public.sap_items(sku),
  brand           text,
  type1           text,                             -- 4W / 2W …
  type2           text,                             -- LTB / TBR / OTR …
  type3           text,                             -- FLAP / TIRE / TUBE …
  qty             integer  not null,
  unit_price_idr  numeric  not null,                -- Unit Price (IDR)
  unit_cost_idr   numeric  not null,                -- P_Price (IDR) 매입단가
  sales_idr       numeric  not null,                -- Discounted Amount (IDR) 할인 후 매출
  status          text     not null check (status in ('DLV','DLV_CXL')),
  delivery_date   date
);

comment on table public.margin_lines is
  '마진 명세 — sales analysis report <YYYY-MM>.xlsx 의 1.Row_Data 시트. 축 교차 필터(고객×SKU 등)용. 원가/마진은 v_margin_lines 에서 계산.';

create index margin_lines_ym_idx         on public.margin_lines (year_month);
create index margin_lines_ym_partner_idx on public.margin_lines (year_month, partner_id);
create index margin_lines_ym_sku_idx     on public.margin_lines (year_month, sku);
create index margin_lines_doc_idx        on public.margin_lines (doc_no);

alter table public.margin_lines enable row level security;
create policy margin_lines_all_authenticated on public.margin_lines
  for all to authenticated using (true) with check (true);

-- 조회 뷰 — 거래처명·품명을 붙이고 원가·마진을 계산한다.
create or replace view public.v_margin_lines
with (security_invoker = true) as
select
  l.id, l.year_month, l.doc_no, l.status, l.delivery_date,
  l.partner_id, p.name  as buyer,
  l.sku,        i.description,
  l.brand, l.type1, l.type2, l.type3,
  l.qty,
  l.unit_price_idr,
  l.sales_idr,
  (l.qty * l.unit_cost_idr)                    as cost_idr,
  (l.sales_idr - l.qty * l.unit_cost_idr)      as margin_idr,
  case when l.sales_idr <> 0
       then (l.sales_idr - l.qty * l.unit_cost_idr) / l.sales_idr * 100
  end                                          as margin_pct
from public.margin_lines l
join public.sap_partners p on p.id = l.partner_id
join public.sap_items    i on i.sku = l.sku;

comment on view public.v_margin_lines is
  'margin_lines + 거래처명/품명 + 원가·마진 계산. Margin.vue 고객×SKU 교차 필터 조회용.';

-- ── 월별 정합성 대조 뷰 ──────────────────────────────────────────────────────
-- state = ok(요약과 일치) / mismatch(엑셀이 구버전) / none(해당 월 엑셀 없음)
create or replace view public.v_margin_lines_check
with (security_invoker = true) as
select
  m.year_month,
  m.total_sales                                   as summary_sales,
  round(coalesce(l.sales, 0))                     as lines_sales,
  round(coalesce(l.sales, 0) - m.total_sales)     as diff_idr,
  coalesce(l.lines, 0)                            as line_cnt,
  case when l.sales is null then 'none'
       when abs(l.sales - m.total_sales) <= 2 then 'ok'
       else 'mismatch'
  end                                             as state
from public.margin_months m
left join (
  select year_month, sum(sales_idr) sales, count(*) lines
  from public.margin_lines group by 1
) l on l.year_month = m.year_month;

comment on view public.v_margin_lines_check is
  '월별 명세(margin_lines) 합계 vs 요약(margin_months) 대조. state=none 은 엑셀 미보유 월, mismatch 는 엑셀이 구버전인 월(2023-10).';
