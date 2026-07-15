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

## 데이터 SSOT (단일 진실원천)

- **시장/경쟁 + 재무**: `data/kpi/<YYYY>.csv` → `kpi_importer.py` → `kpi_monthly`(`Monitor.vue`). CSV는 정상 UTF-8 한글로 작성.
- **마진 분석**: `sales analysis report_<YYYY-MM>.pdf` → `seed_margin_<YYYY-MM>.sql` → `margin_records`(`Margin.vue`).
- SQL만 DB에 적용했다면 **CSV(SSOT)도 함께 갱신**한다(안 그러면 importer 재실행 시 되돌아감).

## 컨벤션

- 뷰: `<script setup lang="ts">`, Tailwind 다크 테마(`bg-card`·`border`·`text-muted-foreground`·teal 액센트).
- 변경 후 `npm run build` 로 타입/빌드 검증.
- 라우터 역할 게이팅: `super_admin`/`staff`=전체, `distributor`/`end_user`=`/quote`만.
- Supabase service_role 키는 서버/수집기 전용(`VITE_` 접두사 금지). 데이터 보호는 RLS `to authenticated` + 사용자 JWT.
