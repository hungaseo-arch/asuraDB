# CONTRIBUTING

AsuraDB 에 손대기 전에 읽는 문서. 구조는 [ARCHITECTURE.md](ARCHITECTURE.md),
실행·배포는 [README.md](README.md) 를 본다.

사내 전용 저장소라 PR 리뷰 프로세스는 없다. 대신 **아래 규칙을 지키는 것으로 리뷰를 대신한다.**

---

## 0. 작업 완료의 정의

> **작업 완료 = 변경이력 기록 완료.**

의미 있는 변경을 하고도 [docs/웹사이트_운영_변경이력.md](docs/웹사이트_운영_변경이력.md) 에
기록을 남기지 않았다면 그 작업은 끝난 게 아니다. 매 작업 종료 직전 스스로 점검한다.

```markdown
### YYYY-MM-DD — <한 줄 제목>

- **<무엇을>** <어떻게/어디서> (파일·테이블·근거)
- 검증 결과(빌드 통과 / 합계 일치 / dry-run 등)
```

- 항목은 `## 📌 변경이력` 섹션 **맨 위**에 추가한다. 날짜는 절대표기(`2026-09-06`).
- **기록 대상** — 새 페이지·라우트, DB 스키마/데이터 변경, KPI·마진 갱신, 마이그레이션 추가·삭제,
  수집기 변경, 버그 수정, 운영·인프라 변경(LaunchAgent·스케줄), 보안·PII 조치, 빌드/배포 영향.
- **기록 제외** — 오타·포맷팅 등 사소한 정리, 조회만 한 경우.
- 구조·스키마·환경변수가 바뀌었으면 해당 가이드 문서도 함께 고친다.

루트의 [CHANGELOG.md](CHANGELOG.md) 는 릴리스 단위 요약본이라 매 변경마다 손대지 않는다.

---

## 1. 개발 흐름

```bash
git switch -c feat/<주제>     # main 에 직접 커밋하지 않는다
npm run dev                   # http://localhost:5173/asuraDB/
# ... 작업 ...
npm run build                 # vue-tsc + vite build — 통과해야 커밋
```

- **커밋 전 `npm run build` 는 필수.** 타입 오류를 남긴 채 커밋하지 않는다.
- 화면을 건드렸으면 실제로 열어서 눈으로 확인한다. 근태·견적처럼 역할에 따라 보이는 게
  다른 화면은 해당 역할 계정으로 확인한다.
- E2E 스모크: `npm run test:e2e` (전 라우트 렌더 + 콘솔 에러 0건).

**커밋 메시지** — `<type>(<scope>): <한글 요약>` 형태를 쓴다.

```
feat(attendance): 대리출석 방지 Phase 2 — RPC 5종 + 직접 insert 우회 경로 차단
fix(login-history): CSV 인젝션 방지 + 로그 위조 방지 RLS 강화
docs(changelog): 로그인 이력/계정 메뉴 통합 기록
style(branch-sales): 매출/P&L 표 디자인을 LaborCost 기준으로 정리
chore(db): 고아 테이블 branch_ops_monthly 삭제
```

type 은 `feat` · `fix` · `docs` · `style` · `chore` · `refactor` · `recover`.

---

## 2. 코드 컨벤션

### 2.1 Vue

- 전부 `<script setup lang="ts">`. Options API 는 쓰지 않는다.
- 새 화면은 `src/views/` 에 만들고 `src/router/index.ts` 에 **지연 로딩**으로 등록한다.
  `meta.title` · `meta.desc` 를 반드시 채운다(문서 제목·description 갱신에 쓰인다).
- 사이드바 노출이 필요하면 `src/components/Layout.vue` 의 그룹(`perf`/`hr`/`sales`/`ref`/`docs`)에 넣는다.
- 여러 화면이 쓰는 로직은 `src/lib/` 에, 상태는 `src/stores/`(Pinia)에 둔다.

### 2.2 스타일 — 라이트 테마 고정

앱 표준은 **라이트 모드**(2026-07-29 영구 확정). `src/style.css` 의 `:root` 라이트 토큰이
활성이며 `.dark` 는 쓰지 않는다.

- **신규 페이지는 반드시 라이트.** 하드코딩 다크 배경 금지.
- 색은 시맨틱 토큰으로: `bg-background` · `bg-card` · `border` · `text-muted-foreground` · `text-primary`.
- 독립 팔레트가 필요하면 60-30-10 (`#F0F0F0` / `#E3F2FD` / `#E8F5E9` / `#546E7A`) 을 따른다.
  기준 구현은 [src/views/tools/DotLookup.vue](src/views/tools/DotLookup.vue).
- 표·카드·KPI 밀도의 기준본은 [src/views/LaborCost.vue](src/views/LaborCost.vue).

### 2.3 입력창

테두리 박스형 인풋은 쓰지 않는다. 용도에 따라 두 가지만 쓴다(2026-08-19 확정).

| 용도 | 규격 |
|---|---|
| **표 안 인라인 편집** | 평문형 — 평상시 `border-transparent bg-transparent`, hover `bg-[#F0F0F0]`, focus `bg-background` + `ring-1 ring-primary/50` |
| **라벨이 있는 폼** | `.form-grid` / `.form-field` — 필드 `#ECEFF1`, 라벨 12px `#546E7A`(padding-left 12px), 값 14px `#37474F`, focus 시 흰 배경 + `#546E7A` 테두리, 필수는 `<span class="required">*</span>` |

팔레트 밖의 새 색을 임의로 들이지 않는다.

> ⚠ `.form-grid`/`.form-field` 는 아직 `src/style.css` 로 전역화되지 않았다. 현재 정의는
> [src/views/Attendance.vue](src/views/Attendance.vue) 의 `<style scoped>` 와
> [employee-pwa/src/style.css](employee-pwa/src/style.css) 에 각각 있다. 다른 화면에서 쓰려면
> 전역화가 선행돼야 한다(미해결 항목).

### 2.4 숫자·표기

- 숫자는 영미식(콤마 천단위, 마침표 소수점). IDR 대금액은 `juta` / `miliar` / `triliun`.
- **제원(스펙) 표기는 영문·약어로 통일** — `PAT` · `Size` · `PR` · `LI` · `SS` · `RIM` ·
  `OD` · `SW` · `TD` · `Single` · `Dual` · `Pres` · `WT`. 한국어·인니어를 섞지 않는다.
- 단위가 있으면 헤더에 붙인다: `OD (mm)` · `TD (mm)` · `Single (kg)` · `Pres (psi)` · `Qty (EA)`.
- 같은 항목은 화면이 달라도 같은 용어를 쓴다(트레드 깊이/TD 혼용 금지).

### 2.5 계산 기준 (틀리면 숫자가 전부 어긋난다)

- **마진은 항상 판매가 기준** — `마진 = (판매가 − 원가) ÷ 판매가`.
  역산은 `판매가 = 원가 ÷ (1 − 마진)`. 마진 100% 이상 입력은 무효.
  원가 기준 산식(`÷ 원가`)은 어떤 화면·문서·역산에도 쓰지 않는다.
- **가중평균 마진 = 총이익 ÷ 총판매액** (Additional Discount 반영 후, PPN 제외).
- **VAT(PPN 11%)** — 대리점가(`dist_price_pcs`·`dist_price_set`)는 **포함가**,
  그 외(`fob`·`wh_price_pcs`·`wh_price_set`)는 **미포함가**. 외부 자료를 넣을 때는 그 자료의
  VAT 포함 여부를 먼저 확인해 환산한다(포함가 ÷ 1.11). 화면·CSV 헤더에 포함 여부를 병기한다.

---

## 3. 데이터 (SSOT)

숫자를 고칠 때는 **원본 파일과 DB 를 함께** 고친다. SQL 만 적용하면 importer 재실행 때 되돌아간다.

| 도메인 | 원본 | 적재 |
|---|---|---|
| 시장·경쟁·재무 KPI | `data/kpi/<YYYY>.csv` (UTF-8 한글) | `collectors/kpi_importer.py` → `kpi_monthly` |
| 마진 분석 | `sales analysis report_<YYYY-MM>.pdf` | `seed_margin_<YYYY-MM>.sql` → `margin_records` |

---

## 4. DB 마이그레이션

파일은 [supabase/migrations/](supabase/migrations/) 에 두고, **적용은 Supabase SQL Editor 에서
직접 실행**한다(CLI push 는 쓰지 않는다).

```
1. supabase/migrations/<이름>.sql 작성 — 재실행 안전하게(IF NOT EXISTS · CREATE OR REPLACE · DROP POLICY IF EXISTS)
2. 커밋
3. Supabase 대시보드 → SQL Editor 에 붙여넣고 실행
4. 읽기 전용 쿼리로 반영 확인 (정책·함수 시그니처·제약·ACL)
5. Security Advisors 확인 — 새로 뜬 경고가 없는지
6. docs/웹사이트_운영_변경이력.md 에 "프로덕션 반영 확인" 기록
```

**보안 규칙** — 자세한 근거는 [개발 지침서 §11-6](docs/AsuraDB_Development_Guide.md).

- 모든 테이블 정책은 `TO authenticated`. `TO public` 을 쓰지 않는다.
- 역할 판정은 `auth.jwt() -> 'app_metadata' ->> 'role'`. 클라이언트가 보낸 값을 믿지 않는다.
- 역할 비교는 **`IS DISTINCT FROM`** 을 쓴다. `<>` 는 role 이 NULL 일 때 통과하는 fail-open 이다.

  ```sql
  -- 위험 — role 이 NULL 이면 통과한다
  IF (auth.jwt()->'app_metadata'->>'role') <> 'super_admin' THEN RAISE ...
  -- 올바름
  IF (auth.jwt()->'app_metadata'->>'role') IS DISTINCT FROM 'super_admin' THEN RAISE ...
  ```

- **함수 EXECUTE 회수는 `PUBLIC` 부터.** 함수를 만들면 EXECUTE 는 기본적으로 PUBLIC 에 부여된다
  (`pg_proc.proacl` 이 NULL 이거나 `=X/postgres`). `FROM anon, authenticated` 만 쓰면
  **아무것도 회수되지 않는다.**

  ```sql
  -- 효과 없음
  REVOKE EXECUTE ON FUNCTION public.f() FROM anon, authenticated;
  -- 올바름
  REVOKE EXECUTE ON FUNCTION public.f() FROM PUBLIC, anon, authenticated;
  ```

  회수 후 `has_function_privilege('authenticated', 'public.f()', 'EXECUTE')` 로 확인한다.
  트리거 실행은 EXECUTE 권한과 무관하므로 트리거 전용 함수는 회수해도 안전하다.
- SECURITY DEFINER 함수는 파라미터 `p_`, OUT 컬럼 `o_` 접두사를 붙인다(컬럼명 충돌 방지).

---

## 5. 비밀값

- **`VITE_` 접두사가 붙은 값은 빌드 결과에 그대로 박혀 브라우저에 노출된다.**
  service_role 키·API 비밀키에 절대 붙이지 않는다.
- service_role 키는 수집기·Edge Function 등 서버 쪽 전용이다.
- 데이터 보호는 키를 숨겨서가 아니라 **RLS + 사용자 JWT** 로 한다.
- `.env` 는 커밋하지 않는다. 새 키를 추가하면 `.env.example` 에 **값 없이** 항목만 추가한다.

---

## 6. 배포

```bash
npm run deploy        # 대시보드 + PWA
npm run deploy:pwa    # 직원용 PWA 만
supabase functions deploy <name> --project-ref <ref>   # Edge Function
```

> **순서** — 새 RPC 시그니처에 의존하는 프런트를 배포할 때는 **마이그레이션 → 배포** 순서를 지킨다.
> 반대로 하면 출퇴근 같은 기능이 즉시 막힌다.

---

## 7. 학습덱 HTML (`public/docs/`)

새 디자인을 임의로 만들지 않는다. 기준본
[public/docs/phrasal-verbs-deck-200.html](public/docs/phrasal-verbs-deck-200.html) 을 복사해
데이터만 교체하고, [docs/학습덱_HTML_제작지침.md](docs/학습덱_HTML_제작지침.md) 을 그대로 따른다.

핵심 4가지 — ① 앱 시맨틱 토큰 `:root` 고정(라이트) ② 목록 카드 3칸(`.nbox`/`.wbox`/`.ex`)
③ **영어·인니어·한국어 3종 필수 + 인니어 예문 누락 금지** ④ 🔊 TTS 는 문장에만(`en-US`/`id-ID`).
게시판 등록은 `doc_posts` 에 insert(수정 시 `updated_on` 갱신).
