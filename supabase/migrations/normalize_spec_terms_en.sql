-- 제원 용어 영문 통일 (2026-08-04)
--
-- CLAUDE.md 「제원(스펙) 표기 규칙」에 따라 스펙 탭에 노출되는 셀 값의 한국어·인니어를 영문으로 바꾼다.
-- 헤더는 src/views/Databases.vue 의 SpecCol 정의에서 처리하고, 여기서는 데이터만 정리한다.
-- 같은 항목을 다르게 부르던 값(트랙터/Tractor, Loader Tyres/Loader)도 하나로 합친다.

-- ── TUBE: 카탈로그 구분 → 영문 ────────────────────────────────────────────────
update public.specs_tube set category_label = case category_label
  when '표준'          then 'Standard'
  when '고하중'        then 'Heavy Duty'
  when '건설·농업용'    then 'Construction / Agri'
  when '건설용 고하중'  then 'Construction Heavy Duty'
  when '지게차·산업용'  then 'Forklift / Industrial'
  else category_label end
where category_label is not null;

update public.specs_tube
set remarks = 'As printed in catalog; presumed typo of 13.00/14.00-24'
where remarks = '원본 카탈로그 표기 그대로. 13.00/14.00-24의 오기로 추정';

-- ── TBB: 용도의 한글 병기 제거(괄호 앞 영문만 유지) + 비고 영문화 ──────────────
update public.products_spec_tbb
set application = btrim(split_part(application, ' (', 1))
where application like '% (%';

update public.products_spec_tbb set remarks = case remarks
  when '내마모·내펑크 성능 / 일반 포장도로용' then 'Wear & puncture resistant / on-road use'
  when '정하중반경(SLR) 543 mm'              then 'SLR 543 mm'
  when '대체 림 8.0 / 9.0'                   then 'Alt. rim 8.0 / 9.0'
  when 'ML = Mining & Logging / 복륜 사용 불가' then 'ML = Mining & Logging / not for dual fitment'
  else remarks end
where remarks is not null;

-- ── AGR: '트랙터 (Traktor)' → Tractor, 'xxx Tyres' 접미어 정리 ────────────────
update public.products_spec_agr set application = case application
  when '트랙터 (Traktor)'        then 'Tractor'
  when 'Agriculture Tyres'       then 'Agriculture'
  when 'Farm Implement Tyres'    then 'Farm Implement'
  when 'Industrial Tractor Tyres' then 'Industrial Tractor'
  when 'Road Rollers Tyres'      then 'Road Roller'
  when 'Farm (SH111)'            then 'Farm'
  else application end
where application is not null;

-- ── OTR: 용도 접미어 정리 + 주요 특징 영문화 ──────────────────────────────────
update public.products_spec_otr set application = case application
  when 'Loader Tyres' then 'Loader'
  when 'Mine Tyres'   then 'Mine'
  else application end
where application is not null;

update public.products_spec_otr set features = case features
  when '우수한 트랙션, 내마모·내컷팅·내펑크, 높은 하중 지지력'
    then 'Strong traction; wear, cut & puncture resistant; high load capacity'
  when '우수한 트랙션, 낮은 발열, 장거리 운송·고속 내마모 성능'
    then 'Strong traction; low heat build-up; long-haul and high-speed wear resistance'
  when '펜타곤 블록 조합 트랙션 최적화, 오픈 숄더 설계로 자가 세척(Self-Clean) 우수'
    then 'Pentagon block layout for optimized traction; open shoulder for self-cleaning'
  when '광산·건설 노면용 트랜스버스 패턴, 고강도 카커스·내펑크·재생(Recapping) 우수'
    then 'Transverse pattern for mine and construction ground; high-strength carcass, puncture resistant, recappable'
  when '험지용 로드 그레이더 타이어, 고무 보강 센터 러그로 수명 연장'
    then 'Road grader tyre for rough terrain; rubber-reinforced center lug extends service life'
  else features end
where features is not null;
