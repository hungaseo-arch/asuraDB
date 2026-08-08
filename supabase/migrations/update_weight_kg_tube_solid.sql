-- TUBE·SOLID 제품 중량(weight_kg) 반영 — 2026-08-03
--
-- 출처: spec-tube.csv (중량 단위 g → kg 환산), spec-solid-asc.csv / spec-solid-diamond.csv (kg)
-- 대상: products_price.weight_kg (products_priced 뷰를 통해 Databases.vue 「제품 > 스펙」 탭에 노출)
-- 적용 전 TUBE 82건·SOLID 71건 모두 weight_kg NULL → 스펙 탭 Weight 열이 전부 '—' 로 표시되던 문제.
--
-- SKU 보정: spec-tube.csv 의 VA8251675 → VA82516T75A, VA120024TR78 → VA120024T78 (products 기준 표기)
-- 미반영 3건(원천 자료에 해당 규격 없음): 10220070110122000(ASC 7.00-12 S2000),
--                                        10220065110102000(ASC 6.50-10 S2000), VA23910J2(ASC 23*9-10JS2)

-- ── TUBE ──
update public.products_price p set weight_kg = v.w, updated_at = now()
  from (values
    ('VA82520T75', 2.15::numeric), --  [spec-tube.csv]
    ('VA100020T78', 3.48::numeric), -- ASC 10.00-20TR78 [spec-tube.csv]
    ('VA100020T78S', 4.524::numeric), -- ASC 10.00-20TR78 Heavy Duty [spec-tube.csv]
    ('VA1058018T15', 2.12::numeric), -- ASC 10.5/80-18TR15 [spec-tube.csv]
    ('VA110020T78', 3.71::numeric), -- ASC 11.00-20TR78 [spec-tube.csv]
    ('VA110020T78S', 4.973::numeric), -- ASC 11.00-20TR78 Heavy Duty [spec-tube.csv]
    ('VA11224T218', 4.0::numeric), -- ASC 11.2-24TR218 [spec-tube.csv]
    ('VA12165T15', 2.0::numeric), -- ASC 12-16.5TR15 [spec-tube.csv]
    ('VA120020T78', 4.0::numeric), -- ASC 12.00-20TR78 [specs_tube.w_std]
    ('VA120020T78S', 5.07::numeric), -- ASC 12.00-20TR78 Heavy Duty [specs_tube.w_std]
    ('VA120020T179', 4.0::numeric), -- ASC 12.00R20TR179 [spec-tube.csv]
    ('VA120020T179S', 5.07::numeric), -- ASC 12.00R20TR179 Heavy Duty [spec-tube.csv]
    ('VA120024T78', 4.625::numeric), -- ASC 12.00R24TR78 [spec-tube.csv]
    ('VA120024TR78HD', 5.725::numeric), -- ASC 12.00R24TR78 Heavy Duty [spec-tube.csv]
    ('VA12424T218', 4.1::numeric), -- ASC 12.4-24TR218 [spec-tube.csv]
    ('VA1241128T218', 4.16::numeric), -- ASC 12.4/11-28TR218 [spec-tube.csv]
    ('VA1258018T218', 2.38::numeric), -- ASC 12.5/80-18TR218 [spec-tube.csv]
    ('VA131424T78', 5.4::numeric), -- ASC 13.00/14.00R24 TR78 [spec-tube.csv]
    ('VA131424T78S', 6.5::numeric), -- ASC 13.00/14.00R24 TR78 Heavy Duty [spec-tube.csv]
    ('VA131424T179', 5.4::numeric), -- ASC 13.00/14.00R24TR179 [spec-tube.csv]
    ('VA13614926T218', 4.24::numeric), -- ASC 13.6/14.9-26TR218 [spec-tube.csv]
    ('VA13614928T218', 4.85::numeric), -- ASC 13.6/14.9-28 TR218 [spec-tube.csv]
    ('VA140020T78', 4.53::numeric), -- ASC 14.00-20TR78 [spec-tube.csv]
    ('VA140025T179', 4.771::numeric), -- ASC 14.00-25TR179 [spec-tube.csv]
    ('VA140025T179S', 5.851::numeric), -- ASC 14.00-25TR179 Heavy Duty [spec-tube.csv]
    ('VA149247218', 4.955::numeric), -- ASC 14.9-24TR218 [spec-tube.csv]
    ('VA15525T179', 4.771::numeric), -- ASC 15.5-25TR179 [spec-tube.csv]
    ('VA167020T75', 4.53::numeric), -- ASC 16.0/70-20TR75 [spec-tube.csv]
    ('VA160020T78', 5.45::numeric), -- ASC 16.00-20TR78 [spec-tube.csv]
    ('VA160025T179', 6.63::numeric), -- ASC 16.00-25TR179 [spec-tube.csv]
    ('VA160025T179S', 7.5::numeric), -- ASC 16.00-25TR179 Heavy Duty [spec-tube.csv]
    ('VA16924T218', 4.955::numeric), -- ASC 16.9-24TR218 [spec-tube.csv]
    ('VA16928T218', 6.1::numeric), -- ASC 16.9-28TR218 [spec-tube.csv]
    ('VA16928T220', 6.1::numeric), -- ASC 16.9-28TR220 [spec-tube.csv]
    ('VA17525T179', 6.63::numeric), -- ASC 17.5-25TR179 [spec-tube.csv]
    ('VA17525T1175', 6.63::numeric), -- ASC 17.5-25TRJ1175C [spec-tube.csv]
    ('VA18708J2', 0.45::numeric), -- ASC 18*7-8JS2 [specs_tube.w_std]
    ('VA1878J2', 0.45::numeric), -- ASC 18*7-8JS2 [동일 description SKU]
    ('VA180025T179', 9.5::numeric), -- ASC 18.00-25TR179 [spec-tube.csv]
    ('VA18430T218', 6.9::numeric), -- ASC 18.4-30TR218 [spec-tube.csv]
    ('VA18434T218', 7.32::numeric), -- ASC 18.4-34TR218 [spec-tube.csv]
    ('VA19524TR218', 4.955::numeric), -- ASC 19.5-24TR218 [spec-tube.csv]
    ('VA20525T179', 9.5::numeric), -- ASC 20.5-25TR179 [spec-tube.csv]
    ('VA20525T1175', 9.5::numeric), -- ASC 20.5-25TRJ1175C [spec-tube.csv]
    ('VA2189J2', 0.62::numeric), -- ASC 21*8-9JS2 [specs_tube.w_std]
    ('VA23126T179', 11.9::numeric), -- ASC 23.1-26TR179 [spec-tube.csv]
    ('VA23126T218', 11.9::numeric), -- ASC 23.1-26TR218 [spec-tube.csv]
    ('VA23525T179', 11.0::numeric), -- ASC 23.5-25TR179 [spec-tube.csv]
    ('VA23525T1175', 11.0::numeric), -- ASC 23.5-25TRJ1175C [spec-tube.csv]
    ('VA28915T77', 1.28::numeric), -- ASC 28*9-15TR77 [specs_tube.w_std]
    ('VA30015T77', 1.44::numeric), -- ASC 3.00-15TR77 [specs_tube.w_std]
    ('VA4006011555T', 3.235::numeric), -- ASC 4.00/60-15.5TR15 [spec-tube.csv]
    ('VA50012T13', 0.67::numeric), -- ASC 5.00-12TR13 [spec-tube.csv]
    ('VA55013T13', 0.755::numeric), -- ASC 5.50-13TR13 [spec-tube.csv]
    ('VA60014T13', 0.87::numeric), -- ASC 6.00-14TR13 [spec-tube.csv]
    ('VA60015T13', 0.77::numeric), -- ASC 6.00-15TR13 [specs_tube.w_std]
    ('VA60009J2', 0.62::numeric), -- ASC 6.00-9JS2 [specs_tube.w_std]
    ('VA65010J2', 0.71::numeric), -- ASC 6.50-10JS2 [specs_tube.w_std]
    ('VA65014T13', 0.98::numeric), -- ASC 6.50-14TR13 [spec-tube.csv]
    ('VA70012T75', 0.93::numeric), -- ASC 7.00-12TR75 [specs_tube.w_std]
    ('VA70015T75', 1.3::numeric), -- ASC 7.00-15TR75A [spec-tube.csv]
    ('VA70015T75S', 1.69::numeric), -- ASC 7.00-15TR75A Heavy Duty [spec-tube.csv]
    ('VA70016T177', 1.42::numeric), -- ASC 7.00-16TR177A [spec-tube.csv]
    ('VA70016T75', 1.42::numeric), -- ASC 7.00-16TR75A [spec-tube.csv]
    ('VA70016T75S', 1.846::numeric), -- ASC 7.00-16TR75A Heavy Duty [spec-tube.csv]
    ('VA75016T177', 1.5::numeric), -- ASC 7.50-16TR177A [spec-tube.csv]
    ('VA75016T177S', 1.95::numeric), -- ASC 7.50-16TR177A Heavy Duty [spec-tube.csv]
    ('VA75016T75A', 1.5::numeric), -- ASC 7.50-16TR75A [spec-tube.csv]
    ('VA816T13', 1.0::numeric), -- ASC 8-16TR13 [spec-tube.csv]
    ('VA818T13', 1.6::numeric), -- ASC 8-18TR15 [spec-tube.csv]
    ('VA82515T77', 1.44::numeric), -- ASC 8.25-15TR77 [specs_tube.w_std]
    ('VA82516T177', 1.8::numeric), -- ASC 8.25-16TR177A [spec-tube.csv]
    ('VA82516T177S', 2.34::numeric), -- ASC 8.25-16TR177A Heavy Duty [spec-tube.csv]
    ('VA82516T75A', 1.8::numeric), -- ASC 8.25-16TR75A [spec-tube.csv]
    ('VA82520T177A', 2.15::numeric), -- ASC 8.25-20TR177A [spec-tube.csv]
    ('VA82520T75A', 2.15::numeric), -- ASC 8.25-20TR75A [spec-tube.csv (동일 사이즈·밸브)]
    ('VA82520T78S', 2.99::numeric), -- ASC 8.25-20TR78 Heavy Duty [spec-tube.csv]
    ('VA83824T218', 1.9::numeric), -- ASC 8.3/8-24TR218 [spec-tube.csv]
    ('VA90020T78', 2.81::numeric), -- ASC 9.00-20TR78 [spec-tube.csv]
    ('VA90020T78S', 3.653::numeric), -- ASC 9.00-20TR78 Heavy Duty [spec-tube.csv]
    ('VA93924T218', 2.5::numeric) -- ASC 9.3/9-24TR218 [spec-tube.csv]
  ) as v(sku, w)
 where p.sku = v.sku;

-- ── SOLID ──
update public.products_price p set weight_kg = v.w, updated_at = now()
  from (values
    ('10220100110200200', 156.75::numeric), -- ASC 10.00-20 (SMOOTH) [spec-solid-*.csv]
    ('10220100110201000', 169.43::numeric), -- ASC 10.00-20 S2000 [spec-solid-*.csv]
    ('10220015450081000', 9.51::numeric), -- ASC 15*4.5-8 S2000 [spec-solid-*.csv]
    ('10220160110083000', 16.15::numeric), -- ASC 16*6-8 S2000 [spec-solid-*.csv]
    ('10220160110083002', 16.15::numeric), -- ASC 16*6-8 S2000 - 1/2M [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220160110083003', 16.15::numeric), -- ASC 16*6-8 S2000 NON MARKING [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220180110081000', 20.59::numeric), -- ASC 18*7-8 S2000 [spec-solid-*.csv]
    ('10220180110081001', 20.59::numeric), -- ASC 18*7-8 S2000 - 1/2M [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220180110081003', 20.59::numeric), -- ASC 18*7-8 S2000 NON MARKING [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220200500102000', 24.89::numeric), -- ASC 2.00/50-10 S2000 [spec-solid-*.csv]
    ('10220025110152000', 68.13::numeric), -- ASC 2.50-15 S2000 [spec-solid-*.csv]
    ('10220025110151000', 68.13::numeric), -- ASC 2.50-15 S2000 [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220210110093000', 35.09::numeric), -- ASC 21*8-9 S2000 [spec-solid-*.csv]
    ('10220210110093001', 35.09::numeric), -- ASC 21*8-9 S2000 - 1/2M [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220210110093003', 35.09::numeric), -- ASC 21*8-9 S2000 NON MARKING [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220023010122000', 51.81::numeric), -- ASC 23*10-12 S2000 [spec-solid-*.csv]
    ('10220230110093000', 48.31::numeric), -- ASC 23*9-10 S2000 [spec-solid-*.csv]
    ('10220230110093001', 48.31::numeric), -- ASC 23*9-10 S2000 - 1/2M [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220230110093003', 48.31::numeric), -- ASC 23*9-10 S2000 NON MARKING [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220081110152000', 59.68::numeric), -- ASC 28*9-15 (8.15-15) S2000 [spec-solid-*.csv]
    ('10220081110152001', 59.68::numeric), -- ASC 28*9-15 (8.15-15) S2000 - 1/2M [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220081110152003', 59.68::numeric), -- ASC 28*9-15 (8.15-15) S2000 NON MARKING [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220030110151000', 107.22::numeric), -- ASC 3.00-15 S2000 [spec-solid-*.csv]
    ('10220300110153000', 107.22::numeric), -- ASC 3.00-15 S2000 [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220300110153001', 107.22::numeric), -- ASC 3.00-15 S2000 - 1/2M [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220040110080200', 11.14::numeric), -- ASC 4.00-8 S200 [spec-solid-*.csv]
    ('10220050110081000', 16.33::numeric), -- ASC 5.00-8 S2000 [spec-solid-*.csv]
    ('10220050110081001', 16.33::numeric), -- ASC 5.00-8 S2000 - 1/2M [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220050110081003', 16.33::numeric), -- ASC 5.00-8 S2000 NON MARKING [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220060110152000', 42.98::numeric), -- ASC 6.00-15 S2000 [spec-solid-*.csv]
    ('10220060110091000', 28.32::numeric), -- ASC 6.00-9 S1000 [spec-solid-*.csv]
    ('10220060110093000', 28.32::numeric), -- ASC 6.00-9 S1000 - 1/2M [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220060110091003', 28.32::numeric), -- ASC 6.00-9 S1000 NON MARKING [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220060110092000', 28.3::numeric), -- ASC 6.00-9 S2000 [spec-solid-*.csv]
    ('10220065110101000', 37.92::numeric), -- ASC 6.50-10 S1000 [spec-solid-*.csv]
    ('10220065110101001', 37.92::numeric), -- ASC 6.50-10 S1000 - 1/2M [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220065110101003', 37.92::numeric), -- ASC 6.50-10 S1000 NON MARKING [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220070110121000', 51.04::numeric), -- ASC 7.00-12 S1000 [spec-solid-*.csv]
    ('10220070110123000', 51.04::numeric), -- ASC 7.00-12 S1000 - 1/2M [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220070110121003', 51.04::numeric), -- ASC 7.00-12 S1000 NON MARKING [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220070110151000', 57.31::numeric), -- ASC 7.00-15 S2000 [spec-solid-*.csv]
    ('10220700110153000', 57.31::numeric), -- ASC 7.00-15 S2000 [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220700110153001', 57.31::numeric), -- ASC 7.00-15 S2000 - 1/2M [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220075110163000', 75.05::numeric), -- ASC 7.50-16 S2000 [spec-solid-*.csv]
    ('10220075110163001', 75.05::numeric), -- ASC 7.50-16 S2000 - 1/2M [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220075110163003', 75.05::numeric), -- ASC 7.50-16 S2000 NON MARKING [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220085110153000', 89.76::numeric), -- ASC 8.25-15 S2000 [spec-solid-*.csv]
    ('10220085110153001', 89.76::numeric), -- ASC 8.25-15 S2000 - 1/2M [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220085110153003', 89.76::numeric), -- ASC 8.25-15 S2000 NON MARKING [spec-solid-*.csv (동일 사이즈·패턴)]
    ('10220090110201000', 149.57::numeric), -- ASC 9.00-20 S2000 [spec-solid-*.csv]
    ('1022018011008XN00', 21.16::numeric), -- DIAMOND 18*7-8 XN-028 [spec-solid-*.csv]
    ('1022006511010XN03', 21.16::numeric), -- DIAMOND 18*7-8 XN-028 NON MARKING [spec-solid-*.csv (동일 사이즈·패턴)]
    ('1022021011009XN00', 34.02::numeric), -- DIAMOND 21*8-9 XN-028 [spec-solid-*.csv]
    ('1022006011009XN03', 34.02::numeric), -- DIAMOND 21*8-9 XN-028 NON MARKING [spec-solid-*.csv (동일 사이즈·패턴)]
    ('1022023011009XN00', 47.18::numeric), -- DIAMOND 23*9-10 XN-018 [spec-solid-*.csv]
    ('1022023011009XN02', 47.18::numeric), -- DIAMOND 23*9-10 XN-018 NON MARKING [spec-solid-*.csv (동일 사이즈·패턴)]
    ('1022023011009XN03', 47.18::numeric), -- DIAMOND 23*9-10 XN-018 NON MARKING [spec-solid-*.csv (동일 사이즈·패턴)]
    ('1022008111015XN00', 58.59::numeric), -- DIAMOND 28*9-15 (8.15-15) XN-028 [spec-solid-*.csv]
    ('1022008111015XN03', 58.59::numeric), -- DIAMOND 28*9-15 (8.15-15) XN-028 NON MARKING [spec-solid-*.csv (동일 사이즈·패턴)]
    ('1022005011008XN00', 15.0::numeric), -- DIAMOND 5.00-8 XN-028 [spec-solid-*.csv]
    ('1022005011008XN03', 15.0::numeric), -- DIAMOND 5.00-8 XN-028 NON MARKING [spec-solid-*.csv (동일 사이즈·패턴)]
    ('1022006011009XN00', 24.78::numeric), -- DIAMOND 6.00-9 XN-028 [spec-solid-*.csv]
    ('1022018011008XN03', 24.78::numeric), -- DIAMOND 6.00-9 XN-028 NON MARKING [spec-solid-*.csv (동일 사이즈·패턴)]
    ('1022006511010XN00', 33.53::numeric), -- DIAMOND 6.50-10 XN-028 [spec-solid-*.csv]
    ('1022021011009XN03', 33.53::numeric), -- DIAMOND 6.50-10 XN-028 NON MARKING [spec-solid-*.csv (동일 사이즈·패턴)]
    ('1022007011012XN00', 47.67::numeric), -- DIAMOND 7.00-12 XN-028 [spec-solid-*.csv]
    ('1022007011012XN03', 47.67::numeric), -- DIAMOND 7.00-12 XN-028 NON MARKING [spec-solid-*.csv (동일 사이즈·패턴)]
    ('1022008511015XN00', 92.2::numeric), -- DIAMOND 8.25-15 XN-018 [spec-solid-*.csv]
    ('1022008511015XN03', 92.2::numeric) -- DIAMOND 8.25-15 XN-018 NON MARKING [spec-solid-*.csv (동일 사이즈·패턴)]
  ) as v(sku, w)
 where p.sku = v.sku;

-- ── specs_tube.w_std 를 spec-tube.csv 최신값으로 정정 ──
update public.specs_tube set w_std = 0.755 where sku = 'VA55013T13'; -- 0.78 → 0.755
update public.specs_tube set w_std = 3.653 where sku = 'VA90020T78S'; -- 3.65 → 3.653
update public.specs_tube set w_std = 4.524 where sku = 'VA100020T78S'; -- 4.52 → 4.524
update public.specs_tube set w_std = 4.973 where sku = 'VA110020T78S'; -- 4.97 → 4.973
update public.specs_tube set w_std = 5.725 where sku = 'VA120024TR78HD'; -- 5.73 → 5.725
update public.specs_tube set w_std = 3.235 where sku = 'VA4006011555T'; -- 3.24 → 3.235
update public.specs_tube set w_std = 2.0 where sku = 'VA12165T15'; -- 1.99 → 2.0
update public.specs_tube set w_std = 4.955 where sku = 'VA149247218'; -- 4.96 → 4.955
update public.specs_tube set w_std = 4.955 where sku = 'VA16924T218'; -- 4.96 → 4.955
update public.specs_tube set w_std = 4.955 where sku = 'VA19524TR218'; -- 4.96 → 4.955
update public.specs_tube set w_std = 4.771 where sku = 'VA140025T179'; -- 4.76 → 4.771
update public.specs_tube set w_std = 4.771 where sku = 'VA15525T179'; -- 4.76 → 4.771
update public.specs_tube set w_std = 5.851 where sku = 'VA140025T179S'; -- 5.85 → 5.851
update public.specs_tube set w_std = 4.16 where sku = 'VA1241128T218'; -- 3.85 → 4.16
