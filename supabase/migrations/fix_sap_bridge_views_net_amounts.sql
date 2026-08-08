-- SAP 브리지 뷰 3종 산식 정정 (2026-08-06)
--
-- 원본(SAP AR/AP)은 취소·크레딧메모 문서의 수량·금액을 이미 음수로 담고 있다.
-- 최초 정의는 (1) status='INV' 만 집계해 취소분(INV_CXL)이 빠지고,
-- (2) v_margin_sap_check 는 CM 을 한 번 더 음수화해 부호가 뒤집혔으며,
-- (3) 고객 실적이 할인 전 금액(qty×단가)이라 마진 SSOT 와 기준이 달랐다.
--
-- 정정 기준
--   · 수량·금액은 전 status 합산(부호는 원본에 내장) → 순(net) 값.
--   · 매출 금액은 할인 후 금액(disc_amount_idr) 사용 → margin_months.total_sales 와 동일 기준.
--     (64개월 중 58개월이 ±1% 이내 일치)
--   · 최근 판매/구매 일자는 실제 청구 문서(INV)만 대상.
-- 컬럼 구성은 기존과 동일 — Databases.vue / Margin.vue 수정 불필요.

create or replace view public.v_db_products
with (security_invoker = on) as
select p.id, p.sku, p.item, p.brand, p.description, p.unit, p.is_active,
       coalesce(s.sold_qty, 0)   as sap_sold_qty,
       s.last_sold_date          as sap_last_sold,
       coalesce(b.bought_qty, 0) as sap_bought_qty,
       b.last_bought_date        as sap_last_bought
  from products p
  left join (
    select l.sku,
           sum(l.qty)                                        as sold_qty,
           max(h.inv_date) filter (where h.status = 'INV')   as last_sold_date
      from sap_sales_invoice_lines l
      join sap_sales_invoices h using (doc_no)
     where l.sku is not null
     group by l.sku
  ) s on s.sku = p.sku
  left join (
    select l.sku,
           sum(l.qty)                                        as bought_qty,
           max(h.inv_date) filter (where h.status = 'INV')   as last_bought_date
      from sap_purchase_invoice_lines l
      join sap_purchase_invoices h using (doc_no)
     where l.sku is not null
     group by l.sku
  ) b on b.sku = p.sku;

create or replace view public.v_db_customers
with (security_invoker = on) as
select c.id, c.customer_code, c.customer_name, c.acquirer_name,
       c.main_pic_name, c.assist1_name, c.assist2_name, c.is_active,
       pt.id                          as sap_partner_id,
       coalesce(x.doc_cnt, 0)         as sap_invoice_cnt,
       coalesce(x.sales_idr, 0)       as sap_sales_idr,
       x.last_inv_date                as sap_last_invoice
  from customers c
  left join sap_partners pt on pt.customer_id = c.id
  left join (
    select h.partner_id,
           count(distinct h.doc_no) filter (where h.status = 'INV') as doc_cnt,
           sum(l.disc_amount_idr)                                   as sales_idr,
           max(h.inv_date) filter (where h.status = 'INV')          as last_inv_date
      from sap_sales_invoices h
      join sap_sales_invoice_lines l using (doc_no)
     group by h.partner_id
  ) x on x.partner_id = pt.id;

create or replace view public.v_margin_sap_check
with (security_invoker = on) as
select m.year_month,
       m.total_sales                                       as margin_total_sales,
       coalesce(s.sap_sales, 0)                            as sap_sales,
       round(m.total_sales::numeric - coalesce(s.sap_sales, 0)) as diff_idr,
       case when m.total_sales <> 0
            then round(coalesce(s.sap_sales, 0) / m.total_sales::numeric * 100, 1)
       end                                                 as match_pct
  from margin_months m
  left join (
    select to_char(h.inv_date, 'YYYY-MM') as ym,
           sum(l.disc_amount_idr)         as sap_sales
      from sap_sales_invoice_lines l
      join sap_sales_invoices h using (doc_no)
     where h.inv_date is not null
     group by 1
  ) s on s.ym = m.year_month;
