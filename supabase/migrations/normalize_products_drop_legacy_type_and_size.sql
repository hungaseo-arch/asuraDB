-- 2026-07-14 — products 정규화(3NF): 잉여/죽은 컬럼 정리
-- 근거: 코드 전역 grep 결과 type_1~4·products.size 참조 0건, products_sell 뷰/인덱스 무관 확인
-- 운영 DB(asuradb) 적용 완료.
-- ※ 재실행 안전(멱등): 모든 구문이 이미 적용된 상태에서 다시 실행해도 에러 없이 통과.

-- 1) size: 481행 전부 NULL(죽은 컬럼). 실제 규격은 specs_* 테이블 보유
alter table public.products drop column if exists size;

-- 2) type_1/2/3: category_id(FK→product_categories)와 100% 중복(레거시-only 0행). 이행적 종속 제거
alter table public.products drop column if exists type_1;
alter table public.products drop column if exists type_2;
alter table public.products drop column if exists type_3;

-- 3) type_4: solid 타이어 마킹(black/non_marking, 44행) 실속성 → 의미 있는 이름으로 보존
--    RENAME 은 IF EXISTS 를 못 붙이므로, type_4 가 남아있고 marking 이 아직 없을 때만 개명(멱등 가드)
do $$
begin
  if exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'products' and column_name = 'type_4'
     ) and not exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'products' and column_name = 'marking'
     )
  then
    alter table public.products rename column type_4 to marking;
  end if;
end $$;

-- marking 컬럼 코멘트(이미 존재해도 덮어쓰기만 하므로 재실행 안전)
comment on column public.products.marking is 'solid 타이어 마킹 구분: black / non_marking (구 type_4, 2026-07-14 정규화 시 개명)';
