-- 튜브(HD+)·솔리드 제원 갱신 — Arami 공장 스펙 반영 (2026-10-02)
--
-- 출처
--   · TUBE  : Arami 튜브 스펙표(이미지, 2026-10-02 수신) → AM_Tube_Spec.csv 3행
--   · SOLID : 'Data_Spec_Solid.xlsx' ('Spec All' 시트 + 'Spec' 시트 23x10-12) → Solid_Tire_Spec.csv 67행
--
-- TUBE (쎄오님 결정 2026-10-02: HD+ 는 기존 HD 와 별개 품목으로 신규 등록, Arami 단가는 매입가로 반영)
--   · 신규 제품 3건(products·products_price·specs_tube). SKU 는 기존 HD 체계를 본뜬 임시코드(…HP) —
--     ERP 정식 코드 확정 시 교체 필요(review_note 표기).
--   · 단가 = Arami Price EXC PPN → products_price.wh_price_pcs (VAT 미포함 기준과 일치).
--   · 중량 g → kg 환산(w_std·w_min·w_max·products_price.weight_kg).
--
-- SOLID (쎄오님 결정 2026-10-02: Arami 공장 스펙으로 덮어쓰기)
--   · 갱신 항목 = rim_size · section_width_mm · overall_diameter_mm · weight_kg (하중값은 카탈로그 값 유지).
--   · 매칭 = 제품 설명(products.description)의 브랜드·규격·패턴·NON MARKING 여부.
--     완전일치가 없으면 (브랜드·규격·NM) → (브랜드·규격) 순 폴백(폴백 대상 행은 제원값이 동일함을 확인).
--       폴백 4건: ASC 6.00-9 S1000 / ASC 7.00-12 S1000 (→ 동일 규격 S2000 값과 동일),
--                 ASC 6.50-10 S1000 NON MARKING (→ CSV 6.50-10 NM),
--                 DIAMOND 23*9-10 XN-018 NON MARKING (→ 같은 규격 표준 제원, 기존 처리와 동일).
--   · DIAMOND NON MARKING 4건(XN03: 18*7-8 · 21*8-9 · 6.00-9 · 6.50-10)은 8월 반영 시 규격이 서로 엇갈려
--     붙어 있던 것을 설명 기준 규격으로 바로잡음(size 포함).
--   · 신규 제원 16건: ASC 23*10-12 S2000 1건 + DIAMOND S200 (H) 15건(HUA IN 공장, 제품은 있으나 제원 미등록이던 품목).
--   · 원본 규격 '2.50-15'·'3.00-15' 는 외경상 250-15·300-15 로 보이나 DB 표기는 제품 설명 기준으로 유지.

-- ── TUBE : HD+ 신규 3건 ─────────────────────────────────────────────────────────
insert into public.products (item, brand, description, sku, unit, category_id, factory, is_active)
values
  ('TUBE','ASCENDO','ASC 12.00R24TR78 HD+',       'VA120024T78HP', 'pcs', 10, 'ARAMI', true),
  ('TUBE','ASCENDO','ASC 13.00/14.00R24TR179 HD+','VA131424T179HP','pcs', 10, 'ARAMI', true),
  ('TUBE','ASCENDO','ASC 13.00/14.00R24 TR78 HD+','VA131424T78HP', 'pcs', 10, 'ARAMI', true)
on conflict do nothing;

insert into public.products_price (sku, description, weight_kg, wh_price_pcs, review_field, review_note)
values
  ('VA120024T78HP', 'ASC 12.00R24TR78 HD+',        6.14, 414202, null, 'Arami Price EXC PPN 2026-10-02 / 임시 SKU — ERP 코드 확인 필요'),
  ('VA131424T179HP','ASC 13.00/14.00R24TR179 HD+', 7.90, 527146, null, 'Arami Price EXC PPN 2026-10-02 / 임시 SKU — ERP 코드 확인 필요'),
  ('VA131424T78HP', 'ASC 13.00/14.00R24 TR78 HD+', 7.90, 527146, null, 'Arami Price EXC PPN 2026-10-02 / 임시 SKU — ERP 코드 확인 필요')
on conflict (sku) do update set weight_kg = excluded.weight_kg, wh_price_pcs = excluded.wh_price_pcs,
  review_field = excluded.review_field, review_note = excluded.review_note, updated_at = now();

insert into public.specs_tube (no, category, size, size_label, valve, w_std, w_min, w_max, lebar, tebal,
  packaging, qty, sku, description, category_label, sack_qty, box_qty, remarks, source_catalog)
select coalesce((select max(no) from public.specs_tube),0) + v.o, 'Type 2', v.size, v.size, v.valve, v.ws, v.wmin, v.wmax,
       v.lebar, v.tebal, 'Box', 3, v.sku, v.descr, 'Heavy Duty+', null, 3, 'Factory: ARAMI', 'Arami Tube Spec 2026-10-02'
from (values
  (1,'VA120024T78HP', 'ASC 12.00R24TR78 HD+',       '12.00-24',       'TR78',  6.140, 5.833, 6.447, 330, 3.0),
  (2,'VA131424T179HP','ASC 13.00/14.00R24TR179 HD+','13.00/14.00-24', 'TR179', 7.900, 7.505, 8.295, 340, 3.6),
  (3,'VA131424T78HP', 'ASC 13.00/14.00R24 TR78 HD+','13.00/14.00-24', 'TR78',  7.900, 7.505, 8.295, 340, 3.6)
) as v(o, sku, descr, size, valve, ws, wmin, wmax, lebar, tebal)
where not exists (select 1 from public.specs_tube t where t.sku = v.sku);

-- ── SOLID : Arami 스펙 덮어쓰기 ──────────────────────────────────────────────────
create temp table _arami(brand text, size text, pat text, nm boolean, rim text, sw numeric, od numeric, wt numeric) on commit drop;
insert into _arami values
  ('ASCENDO','4.00-8','S200',false,'3.00D',113,404,11.30),
  ('ASCENDO','5.00-8','S2000',false,'3.00D',120,452,16.35),
  ('ASCENDO','15x4.5-8','S2000',false,'3.00D',109,382,9.70),
  ('ASCENDO','16x6-8','S2000',false,'4.33R',148,415,16.50),
  ('ASCENDO','18x7-8','S2000',false,'4.33R',153,450,20.75),
  ('ASCENDO','6.00-9','S2000',false,'4.00E',145,525,27.60),
  ('ASCENDO','21x8-9','S2000',false,'6.00E',185,522,35.00),
  ('ASCENDO','200/50-10','S2000',false,'6.50F',195,460,26.00),
  ('ASCENDO','6.50-10','S1000',false,'5.00F',168,572,38.00),
  ('ASCENDO','6.50-10','S2000',false,'5.00F',162,572,36.50),
  ('ASCENDO','23x9-10','S2000',false,'6.50F',203,582,48.50),
  ('ASCENDO','7.00-12','S2000',false,'5.00',173,655,48.90),
  ('ASCENDO','2.50-15','S2000',false,'7.00',226,715,69.00),
  ('ASCENDO','6.00-15','S2000',false,'4.50E',153,690,43.00),
  ('ASCENDO','7.00-15','S2000',false,'5.50',171,733,57.70),
  ('ASCENDO','3.00-15','S2000',false,'8.00',258,802,109.00),
  ('ASCENDO','28x9-15','S2000',false,'7.00',212,688,59.20),
  ('ASCENDO','8.25-15','S2000',false,'6.50F',208,810,91.00),
  ('ASCENDO','7.50-16','S2000',false,'6.00',199,780,76.60),
  ('ASCENDO','9.00-20','S2000',false,'7.00',233,997,151.00),
  ('ASCENDO','10.00-20','S2000',false,'7.50',253,1035,170.70),
  ('ASCENDO','10.00-20','SMOOTH',false,'7.50',218,1015,156.75),
  ('ASCENDO','5.00-8','S2000',true,'3.00D',120,452,16.35),
  ('ASCENDO','16x6-8','S2000',true,'4.33R',148,415,16.50),
  ('ASCENDO','18x7-8','S2000',true,'4.33R',153,450,20.75),
  ('ASCENDO','6.00-9','S1000',true,'4.00E',145,525,27.60),
  ('ASCENDO','21x8-9','S2000',true,'6.00E',185,522,35.00),
  ('ASCENDO','6.50-10','S2000',true,'5.00F',168,572,38.00),
  ('ASCENDO','23x9-10','S2000',true,'6.50F',203,582,48.50),
  ('ASCENDO','7.00-12','S1000',true,'5.00',173,655,48.90),
  ('ASCENDO','28x9-15','S2000',true,'7.00',212,688,59.20),
  ('ASCENDO','7.50-16','S2000',true,'6.00',199,780,76.60),
  ('ASCENDO','8.25-15','S2000',true,'6.50F',208,810,91.00),
  ('DIAMOND','5.00-8','XN-028',false,'3.50D',120,452,15.38),
  ('DIAMOND','18x7-8','XN-028',false,'4.33R',154,450,21.80),
  ('DIAMOND','6.00-9','XN-028',false,'4.00E',131,525,25.40),
  ('DIAMOND','6.50-10','XN-028',false,'5.00F',162,562,35.40),
  ('DIAMOND','21x8-9','XN-028',false,'6.00E',185,522,34.38),
  ('DIAMOND','23x9-10','XN-018',false,'6.50E',205,582,47.77),
  ('DIAMOND','7.00-12','XN-028',false,'5.00S',173,655,47.94),
  ('DIAMOND','28x9-15','XN-028',false,'7.00',212,688,59.30),
  ('DIAMOND','8.25-15','XN-018',false,'6.50',208,810,90.50),
  ('DIAMOND','5.00-8','XN-028',true,'3.50D',120,452,15.38),
  ('DIAMOND','18x7-8','XN-028',true,'4.33R',154,450,21.80),
  ('DIAMOND','6.00-9','XN-028',true,'4.00E',131,525,25.30),
  ('DIAMOND','21x8-9','XN-028',true,'6.00E',185,522,34.38),
  ('DIAMOND','6.50-10','XN-028',true,'5.00F',162,562,35.40),
  ('DIAMOND','7.00-12','XN-028',true,'5.00S',173,655,47.94),
  ('DIAMOND','28x9-15','XN-028',true,'7.00',212,688,59.30),
  ('DIAMOND','8.25-15','XN-018',true,'6.50',208,810,92.00),
  ('ASCENDO','23x10-12','S2000',false,'8.00G',237,592,51.80);

create temp table _prod on commit drop as
select p.sku, p.brand, p.description,
  regexp_replace(replace(replace(lower(split_part(p.description,' ',2)),'*','x'),'2.00/50-10','200/50-10'),'x7\.00-8','x7-8') as ksize,
  case when p.description ilike '%XN-028%' then 'XN-028' when p.description ilike '%XN-018%' then 'XN-018'
       when p.description ilike '%S2000%'  then 'S2000'  when p.description ilike '%S1000%'  then 'S1000'
       when p.description ilike '%SMOOTH%' then 'SMOOTH' when p.description ilike '%S200%'   then 'S200' end as kpat,
  p.description ilike '%NON MARKING%' as knm
from public.products p where p.item = 'SOLID';

update public.products_spec_solid s set
  size = upper(m.ksize),
  rim_size = m.rim, section_width_mm = m.sw, overall_diameter_mm = m.od, weight_kg = m.wt,
  remarks = case when m.lvl = 1 and s.remarks like 'Non-marking item; catalog has no separate spec, same-size standard spec applied%'
                 then replace(s.remarks, 'Non-marking item; catalog has no separate spec, same-size standard spec applied', 'Non-marking item')
                 else s.remarks end,
  source_catalog = coalesce(s.source_catalog || ' / ', '') || 'RIM·SW·OD·WT: Arami Data Spec Solid 2026-10-02'
from (
  select pr.sku, pr.ksize, x.*
  from _prod pr
  cross join lateral (
    select a.rim, a.sw, a.od, a.wt, l.lvl
    from _arami a
    join (values (1),(2),(3)) l(lvl) on
         (l.lvl = 1 and a.brand = pr.brand and a.size = pr.ksize and a.pat = pr.kpat and a.nm = pr.knm)
      or (l.lvl = 2 and a.brand = pr.brand and a.size = pr.ksize and a.nm = pr.knm)
      or (l.lvl = 3 and a.brand = pr.brand and a.size = pr.ksize)
    order by l.lvl, a.pat = pr.kpat desc limit 1
  ) x
) m
where s.sku = m.sku;

-- 신규 제원: ASC 23*10-12 S2000
insert into public.products_spec_solid (sku, brand, series, pattern, size, tire_type, rim_size, overall_diameter_mm, section_width_mm, weight_kg, remarks, source_catalog)
select '10220023010122000','ASCENDO','S2000','S2000','23X10-12','Solid','8.00G',592,237,51.8,
       'From Spec sheet only (factory not stated)','Arami Data Spec Solid 2026-10-02'
where not exists (select 1 from public.products_spec_solid where sku = '10220023010122000');

-- 신규 제원: DIAMOND S200 (H) 15건 — HUA IN
create temp table _huain(brand text, size text, pat text, nm boolean, rim text, sw numeric, od numeric, wt numeric) on commit drop;
insert into _huain values
  ('DIAMOND','6.50-10','S200',false,'5.00F',140,555,34.20),
  ('DIAMOND','28x9-15','S200',false,'7.00',200,685,59.80),
  ('DIAMOND','7.00-12','S200',false,'5.00S',170,635,50.10),
  ('DIAMOND','6.00-9','S200',false,'4.00E',135,520,25.80),
  ('DIAMOND','18x7-8','S200',false,'4.33R',145,428,20.80),
  ('DIAMOND','8.25-15','S200',false,'6.50F',185,790,83.70),
  ('DIAMOND','5.00-8','S200',false,'3.00D',118,445,17.10),
  ('DIAMOND','21x8-9','S200',false,'6.00E',180,490,34.00),
  ('DIAMOND','3.00-15','S200',false,'8.00',235,780,99.50),
  ('DIAMOND','23x9-10','S200',false,'6.50F',200,580,50.80),
  ('DIAMOND','7.50-16','S200',false,'6.00',215,850,81.60),
  ('DIAMOND','16x6-8','S200',false,'4.33R',130,395,15.50),
  ('DIAMOND','2.50-15','S200',false,'7.00/7.50',215,695,66.40),
  ('DIAMOND','4.00-8','S200',false,'3.00D',105,400,11.90),
  ('DIAMOND','200/50-10','S200',false,'6.50F',165,440,20.90),
  ('DIAMOND','15x4.5-8','S200',false,'3.00D',100,368,9.00);

insert into public.products_spec_solid (sku, brand, series, pattern, size, tire_type, rim_size, overall_diameter_mm, section_width_mm, weight_kg, remarks, source_catalog)
select pr.sku, 'DIAMOND', 'S200', 'S200', upper(pr.ksize), 'Solid', h.rim, h.od, h.sw, h.wt, 'Factory: HUA IN', 'Arami Data Spec Solid 2026-10-02'
from _prod pr
join _huain h on h.size = case pr.ksize when '200x50-10' then '200/50-10' else pr.ksize end
where pr.brand = 'DIAMOND' and pr.kpat = 'S200'
  and not exists (select 1 from public.products_spec_solid s where s.sku = pr.sku);
