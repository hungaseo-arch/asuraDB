-- 2026-10-14 가격 정리 (사용자 확정)
--   ① 대리점가 VAT 기준 컬럼 신설 + 옛 규칙(VAT 포함 저장) 대리점가 중 계산이 맞는 품목만 ÷1.11 환산
--   ② 신규 가격표 품명·PR 로 교체 (SKU 기준)
--   ③ 가격 없는 제품 4종 삭제
-- 백업: products_price_backup_20261014(가격) · products_backup_20261014(제품) · products_spec_tbr_backup_20261014
begin;

-- ── 백업 ─────────────────────────────────────────────────────────
create table if not exists products_backup_20261014 as
  select * from products where sku in ('PNE-1878-AB700','PNE-25015-AB700','AGR-20838R1W12','11R225TOT18',
    'R1-31580225AR69820','29580R225TKSH18','120024TKAMIIXL20','10120070200121001');
create table if not exists products_spec_tbr_backup_20261014 as
  select * from products_spec_tbr where sku = '11R225TOT18';
create table if not exists products_price_backup_20261014 as select * from products_price where false;
insert into products_price_backup_20261014
  select * from products_price pp
   where pp.sku not in (select sku from products_price_backup_20261014)
     and (pp.dist_price_pcs > 0 or pp.dist_price_set > 0 or pp.sku in ('PNE-1878-AB700','PNE-25015-AB700',
          'AGR-20838R1W12','11R225TOT18','R1-31580225AR69820','29580R225TKSH18','120024TKAMIIXL20'));

-- 백업 테이블은 public 스키마라 PostgREST 로 노출됨(원가 포함) → RLS 켜고 anon/authenticated 권한 회수
alter table products_price_backup_20261014     enable row level security;
alter table products_backup_20261014           enable row level security;
alter table products_spec_tbr_backup_20261014  enable row level security;
revoke all on products_price_backup_20261014, products_backup_20261014, products_spec_tbr_backup_20261014
  from anon, authenticated;

-- ── ① 대리점가 VAT 기준 컬럼 ──────────────────────────────────────
--   'excl' = VAT 별도 (표준, 계산에 그대로 사용)
--   'incl' = VAT 포함 (옛 규칙 그대로 남은 값 — 계산 시 ÷1.11)
--   null   = 미확인 (값 검토 필요)
alter table products_price add column if not exists dist_vat_basis text not null default 'excl';
alter table products_price alter column dist_vat_basis drop not null;
alter table products_price drop constraint if exists products_price_dist_vat_basis_chk;
alter table products_price add constraint products_price_dist_vat_basis_chk
  check (dist_vat_basis is null or dist_vat_basis in ('excl','incl'));
comment on column products_price.dist_vat_basis is
  '대리점가(dist_price_pcs/set) 저장 기준: excl=VAT 별도(표준) · incl=VAT 포함(옛 규칙 잔존, 계산 시 ÷1.11) · null=미확인';

-- 환산 대상: 10-09 이전 갱신 + 대리점가 있음 + GIS 제외 + ÷1.11 후 마진이 정상 범위(24.5~27.5%)
-- (SQL Editor 는 문장별로 커밋할 수 있어 임시 테이블 대신 인라인 서브쿼리 사용.
--  제외 표시를 먼저 하고 환산을 나중에 한다 — 환산이 updated_at 을 바꾸므로 재실행해도 이중 환산되지 않음)
update products_price pp set
  dist_vat_basis = case when o.brand = 'GIS' then null else 'incl' end,
  review_note    = concat_ws(' · ', nullif(pp.review_note, ''),
                     case when o.brand = 'GIS' then '2026-10-14 대리점가 VAT 기준 미확인(원가 대비 마진 이상)'
                          else '2026-10-14 대리점가 VAT 포함 유지(환산 후 마진이 표준과 달라 보류)' end)
  from (select pp2.sku, p.brand,
               ((pp2.dist_price_pcs / 1.11) - pp2.wh_price_pcs) / (pp2.dist_price_pcs / 1.11) * 100 as m_conv
          from products_price pp2 join products p using (sku)
         where (pp2.dist_price_pcs > 0 or pp2.dist_price_set > 0) and pp2.updated_at < '2026-10-09'
           and coalesce(pp2.review_note, '') not like '%2026-10-14 대리점가%') o
 where pp.sku = o.sku and not (o.brand <> 'GIS' and coalesce(o.m_conv between 24.5 and 27.5, false));

update products_price pp set
  dist_price_pcs = round(pp.dist_price_pcs / 1.11),
  dist_price_set = round(pp.dist_price_set / 1.11),
  dist_vat_basis = 'excl',
  review_note    = concat_ws(' · ', nullif(pp.review_note, ''), '2026-10-14 대리점가 VAT 포함→별도 환산(÷1.11)'),
  updated_at     = now()
  from products p
 where p.sku = pp.sku and p.brand <> 'GIS'
   and (pp.dist_price_pcs > 0 or pp.dist_price_set > 0) and pp.updated_at < '2026-10-09'
   and coalesce(pp.review_note, '') not like '%2026-10-14 대리점가%'
   and ((pp.dist_price_pcs / 1.11) - pp.wh_price_pcs) / (pp.dist_price_pcs / 1.11) * 100 between 24.5 and 27.5;

-- 뷰에 컬럼 추가 (기존 컬럼 순서 유지, 끝에 덧붙임)
create or replace view public.products_priced with (security_invoker = true) as
 select p.id, p.item, p.brand, p.description, p.sku, p.is_active, p.created_at, p.updated_at, p.unit,
        p.category_id, p.factory, p.hs_code,
        pp.weight_kg, pp.fob, pp.qty_40ft, pp.wh_price_pcs, pp.wh_price_set, pp.dist_price_pcs, pp.dist_price_set,
        pp.wh_price_basis, pp.review_field, pp.review_note,
        pp.dist_vat_basis
   from products p
   left join products_price pp on pp.sku = p.sku;

-- ── ② 신규 품명·PR 교체 (SKU 기준, 가격 = 신규 가격표 ÷ 1.11) ─────────
update products p set description = v.d, updated_at = now()
  from (values ('R1-31580225AR69820','ASC 315/80R22.5 AR698 18'),
               ('29580R225TKSH18',   'TK 295/80R22.5 TKSH III 20'),
               ('120024TKAMIIXL20',  'TK 12.00R24 TKAM III XL 20'),
               ('10120070200121001', 'TR 7.00-16 HS307 14')) v(sku, d)
 where p.sku = v.sku;

update products_price pp set description = v.d, wh_price_pcs = v.wp,
       wh_price_set = coalesce(v.ws, pp.wh_price_set), updated_at = now()
  from (values ('R1-31580225AR69820','ASC 315/80R22.5 AR698 18',   3440000, null::numeric),
               ('29580R225TKSH18',   'TK 295/80R22.5 TKSH III 20', 3178000, null),
               ('120024TKAMIIXL20',  'TK 12.00R24 TKAM III XL 20', 4565000, 4922270)) v(sku, d, wp, ws)
 where pp.sku = v.sku;
update products_price set description = 'TR 7.00-16 HS307 14' where sku = '10120070200121001';

-- ── ③ 가격 없는 제품 삭제 (products_price CASCADE · sap_items SET NULL) ──
delete from products_spec_tbr where sku = '11R225TOT18';
delete from products where sku in ('PNE-1878-AB700','PNE-25015-AB700','AGR-20838R1W12','11R225TOT18');

commit;
