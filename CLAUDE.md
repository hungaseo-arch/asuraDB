# AsuraDB — 작업 지침 (CLAUDE.md)

타이어 사업 대시보드 (Vue 3 + TailwindCSS v4 + Supabase + FastAPI).

## ⭐ 필수 — 변경 주요사항은 항상 .md(변경이력)에 기록

> **원칙: "작업 완료 = 변경이력 기록 완료".** 의미 있는 변경을 하고도 기록을 남기지 않으면
> 그 작업은 끝난 것이 아니다. 매 작업(및 세션) 종료 직전, 기록 여부를 반드시 자체 점검한다.

코드·데이터·DB·설정·운영 등 **의미 있는 변경을 완료할 때마다**, 반드시
[`docs/웹사이트_운영_변경이력.md`](docs/웹사이트_운영_변경이력.md) 의 `## 📌 변경이력` 섹션
**맨 위에** 한 항목을 추가한다. (작업 종료 전 빠뜨리지 말 것)

**기록 형식:**
```markdown
### YYYY-MM-DD — <한 줄 제목>

- **<무엇을>** <어떻게/어디서> (파일·테이블·근거)
- 검증 결과(빌드 통과 / 합계 일치 / dry-run 등)가 있으면 함께 기록
```

**기록 대상(예):** 새 페이지·뷰·라우트, DB 스키마/데이터 upsert·삭제·정정, KPI·마진 등 월간 데이터 갱신,
마이그레이션 파일 추가/삭제/리네임, 수집기(collector)·importer 변경, 문서 구조 개편, 빌드/배포 영향이 있는 수정,
**버그 수정, 운영·인프라 변경(LaunchAgent·서버 기동/스케줄 등), 보안·민감정보(PII) 조치.**

**기록 제외:** 오타·포맷팅 등 사소한 정리, 탐색/조회만 한 경우.

> 날짜는 절대표기(예: 2026-06-09). 여러 변경을 한 세션에서 했으면 한 항목에 하위 불릿으로 묶어도 된다.
> 아키텍처·스키마·환경변수 등 구조적 변경이면 해당 가이드 문서(아래 문서 맵)도 함께 갱신한다.

## 문서 맵 (docs/)

- **AsuraDB_Development_Guide.md** — 아키텍처·스키마·환경변수·Supabase 연결/보안(§11)·로드맵·부록 A(마이그레이션)
- **AsuraDB_지표수집_가이드.md** — 외부 거시·시장 지표 24종 수집
- **웹사이트_운영_변경이력.md** — 월간 데이터 갱신 절차 + **변경이력(changelog)** ← 위 지침의 기록처
- **학습덱_HTML_제작지침.md** — `public/docs/` 학습용 정적 HTML 덱 표준 규격 ← 덱 추가·수정 전 필독

## 데이터 SSOT (단일 진실원천)

- **시장/경쟁 + 재무**: `data/kpi/<YYYY>.csv` → `kpi_importer.py` → `kpi_monthly`(`Monitor.vue`). CSV는 정상 UTF-8 한글로 작성.
- **마진 분석**: `sales analysis report_<YYYY-MM>.pdf` → `seed_margin_<YYYY-MM>.sql` → `margin_records`(`Margin.vue`).
- SQL만 DB에 적용했다면 **CSV(SSOT)도 함께 갱신**한다(안 그러면 importer 재실행 시 되돌아감).

## 컨벤션

- 뷰: `<script setup lang="ts">`, **Tailwind 라이트 테마**(`bg-background`·`bg-card`·`border`·`text-muted-foreground`·`text-primary`). 앱 표준은 라이트 모드(2026-07-29 확정) — `src/style.css` 의 `:root` 라이트 토큰이 활성이며 `.dark` 는 사용하지 않는다. **신규 페이지는 반드시 라이트**로 작성(하드코딩 다크 배경 금지, 시맨틱 토큰 사용). 독립 팔레트가 필요한 페이지는 `DotLookup.vue` 의 60-30-10(#F0F0F0/#E3F2FD/#E8F5E9/#546E7A)을 참고.
- 변경 후 `npm run build` 로 타입/빌드 검증.
- **`public/docs/` 학습덱 HTML**: 신규 추가·수정 시 [`docs/학습덱_HTML_제작지침.md`](docs/학습덱_HTML_제작지침.md) 를 **그대로** 따른다. 새 디자인을 임의로 만들지 말고 기준본 [`public/docs/phrasal-verbs-deck-200.html`](public/docs/phrasal-verbs-deck-200.html) 을 복사해 데이터만 교체한다. 핵심 4가지 — ① 앱 시맨틱 토큰 `:root` 고정(라이트) ② 목록 카드 3칸(`.nbox`/`.wbox`/`.ex`) ③ **영어·인니어·한국어 3종 필수 + 인니어 예문 누락 금지** ④ 🔊 TTS 는 문장에만(`en-US`/`id-ID`). 게시판 등록은 `doc_posts`(신규 insert / 수정 시 `updated_on` 갱신).
- **제원(스펙) 표기 규칙** — `Databases.vue` 스펙 탭을 비롯해 제원표를 만드는 모든 화면·문서에 적용:
  - **용어는 영문으로 통일**한다. 헤더·셀 값 모두 한국어·인니어를 쓰지 않는다(예: 구분→`Type`, 고하중→`Heavy Duty`, 건설·농업용→`Construction / Agri`, 폭(lebar)→`Width`, 두께(tebal)→`Thick`).
  - **같은 항목은 같은 용어**로 쓴다. 탭마다 다른 이름(트레드 깊이 / TD, 최대 하중 / 하중능력 / Load Capacity)을 섞지 말고 확인 후 하나로 통일한다.
  - **가능한 약어를 쓴다**: `PAT`(Pattern) · `Size` · `PR` · `LI`(Load Index) · `SS`(Speed Symbol) · `RIM` · `OD` · `SW` · `TD` · `Single` · `Dual` · `Pres` · `WT`(Weight).
  - **단위가 있는 항목은 반드시 단위를 표기**한다: `OD (mm)` · `SW (mm)` · `TD (mm)` · `Single (kg)` · `Dual (kg)` · `Pres (psi)` · `WT (kg)` · `Qty (EA)`.
- **가격 부가세(PPN) 기준** — **대리점가(`dist_price_pcs`·`dist_price_set`)는 VAT 포함가, 그 외 가격
  (`fob`·`wh_price_pcs`·`wh_price_set`)은 VAT 미포함가.** 외부 자료(대시보드·거래처 가격표)를 반영할 때는
  그 자료의 VAT 포함 여부를 먼저 확인하고 이 기준으로 환산해 넣는다(인니 PPN 11% → 포함가 ÷ 1.11).
  화면·CSV 헤더에도 `VAT 별도`/`VAT 포함` 을 병기한다.
- 라우터 역할 게이팅: `super_admin`/`staff`=전체, `distributor`/`end_user`=`/quote`만.
- Supabase service_role 키는 서버/수집기 전용(`VITE_` 접두사 금지). 데이터 보호는 RLS `to authenticated` + 사용자 JWT.
