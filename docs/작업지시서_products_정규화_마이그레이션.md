# 작업지시서 — products 정규화 마이그레이션 실행 (VSCode)

| 항목 | 내용 |
|---|---|
| **작업명** | products 테이블 정규화(3NF) — 레거시 분류·죽은 컬럼 정리 |
| **대상 파일** | `supabase/migrations/normalize_products_drop_legacy_type_and_size.sql` |
| **대상 DB** | Supabase 프로젝트 `asuradb` (ref: `subatvlyfglztdmyexfl`) |
| **작성일** | 2026-07-14 |
| **현재 상태** | ⚠️ **운영 DB 이미 적용 완료** — 본 지시서는 (1) 재현/검증, (2) 타 환경(로컬·복제본) 적용용 |
| **재실행 안전성** | ✅ **멱등(idempotent)** — 이미 적용된 DB에 다시 실행해도 에러 없이 통과 |

---

## 1. 작업 목적

`products` 테이블의 **잉여(redundant) 컬럼**과 **죽은 컬럼(dead column)**을 제거해 정규화 정합성(3NF)을 확보한다.

| 컬럼 | 조치 | 근거 |
|---|---|---|
| `size` | DROP | 481행 전부 NULL. 실제 규격(*ukuran*)은 `specs_*` 테이블이 원본 |
| `type_1 / type_2 / type_3` | DROP | `category_id`(FK→`product_categories`)와 100% 중복 → 이행적 종속(*transitive dependency* / *ketergantungan transitif*) 제거 |
| `type_4` | RENAME → `marking` | solid 타이어 마킹값(black/non_marking, 44행)은 분류가 아닌 실속성 → 보존 |

---

## 2. 사전 조건 (Pre-check)

1. **최신 파일 확인**: VSCode에서 대상 SQL 파일이 아래 "멱등 버전"인지 확인 (핵심: `type_4` 개명 부분이 `do $$ … end $$;` 블록으로 감싸져 있어야 함).
2. **적용 이력 확인 쿼리** — 실행 전 현재 컬럼 상태를 먼저 조회한다.

```sql
select
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='products' and column_name='type_4') as has_type_4,
  exists(select 1 from information_schema.columns
         where table_schema='public' and table_name='products' and column_name='marking') as has_marking;
```

| 결과 | 의미 | 조치 |
|---|---|---|
| `has_type_4=false, has_marking=true` | **이미 적용됨** | 재실행해도 무해(멱등). 검증(4장)만 수행 |
| `has_type_4=true, has_marking=false` | **미적용** | 3장 절차로 실행 |

---

## 3. 실행 절차 (VSCode)

> 이 리포지토리는 `.env`에 `DATABASE_URL`(psql 접속정보)이 없고 npm 마이그레이션 스크립트도 없다.
> 따라서 아래 **방법 A(SQL Editor)** 를 표준으로 하고, psql 직결이 필요하면 방법 B를 사용한다.

### 방법 A — Supabase SQL Editor (표준·권장)

1. VSCode에서 `supabase/migrations/normalize_products_drop_legacy_type_and_size.sql` 열기 → **전체 복사**.
2. 브라우저: Supabase Dashboard → 프로젝트 `asuradb` → **SQL Editor** → **New query**.
3. 붙여넣기 → **Run** (⌘/Ctrl + Enter).
4. `Success. No rows returned` 확인 → 4장 검증으로 이동.

### 방법 B — psql 직결 (VSCode 터미널)

1. Dashboard → **Project Settings → Database → Connection string → URI** 복사 (DB 비밀번호 포함). Session pooler URI 권장.
2. VSCode 통합 터미널에서 실행:

```bash
# 접속 문자열은 셸 히스토리에 남지 않도록 변수로 주입
read -rs PGURI   # 프롬프트에 URI 붙여넣고 Enter
psql "$PGURI" -f supabase/migrations/normalize_products_drop_legacy_type_and_size.sql
```

3. `ALTER TABLE` / `DO` / `COMMENT` 출력 확인.

### 방법 C — VSCode DB 확장 (선택)

`SQLTools` + PostgreSQL 드라이버 또는 Supabase 확장을 쓰면 파일을 우클릭 → **Run on active connection** 으로 실행 가능. 접속정보는 방법 B의 URI를 등록한다.

> ❌ `supabase db push` 는 사용하지 말 것 — 본 리포의 마이그레이션 파일은 CLI 타임스탬프 규칙(`YYYYMMDDHHMMSS_*.sql`)을 따르지 않아 마이그레이션 히스토리 테이블과 어긋난다.

---

## 4. 검증 (Verification)

실행 후 아래 3개 쿼리로 확인한다.

```sql
-- (1) 대상 컬럼 상태: 'marking' 만 남아야 정상
select string_agg(column_name, ', ' order by column_name) as remaining_target_cols
from information_schema.columns
where table_schema='public' and table_name='products'
  and column_name in ('size','type_1','type_2','type_3','type_4','marking');
-- 기대값: marking

-- (2) marking 데이터 보존: 44행(black 24 / non_marking 20)
select marking, count(*) from public.products where marking is not null group by 1 order by 2 desc;

-- (3) 총 행수 불변: 481
select count(*) as total_products from public.products;
```

**합격 기준**: (1)=`marking`, (2) 합계 44행, (3)=481.

---

## 5. 롤백 참고 (주의)

컬럼 DROP은 **되돌릴 수 없다**. 롤백 스크립트는 컬럼을 **다시 만들 뿐 데이터는 복원하지 못한다**.
- `type_1/2/3`: `category_id` 로 100% 대체 가능하므로 실질 손실 없음(원한다면 `product_categories` 조인으로 재구성).
- `size`: 원래 전부 NULL이라 손실 없음.
- `marking`: 개명이므로 데이터 유지. 필요 시 `alter table products rename column marking to type_4;` 로 원복.

전체 원복이 꼭 필요하면 적용 직전 스냅샷(Dashboard → Database → Backups) 시점으로 복구한다.

---

## 6. 완료 후 처리

- [ ] 4장 검증 3건 합격 확인
- [ ] `docs/웹사이트_운영_변경이력.md` 최상단 항목 존재 확인 (2026-07-14 products 정규화) — *기적용 시 이미 기록됨*
- [ ] 앱 영향 없음 재확인: 프론트/수집기에서 `type_1~4`·`products.size` 참조 0건(기검증). 배포 불필요.
