# 작업지시서: 자료실 문서 비공개 전환 (Supabase Storage private bucket)

- 작성일: 2026-10-10
- 대상 저장소: `/Users/seojonghwan/dev/asuraDB` (GitHub `hungaseo-arch/asuraDB`, Vue 3 + Vite + TS, GitHub Pages 배포)
- 작업자: Claude Code (VS Code)
- 승인자: 서종환

---

## 1. 목적

자료실(`#/seo-docs` 개인자료, `#/docs` ASCENDO자료)의 HTML 문서를 **로그인한 사용자만** 볼 수 있게 한다.

현재 문제:
- 본문 HTML이 `public/docs/<file>.html`에 있어 `https://hungaseo-arch.github.io/asuraDB/docs/<file>.html`로 **로그인 없이 누구나 열람 가능**.
- 저장소가 public이라 GitHub에서도 원문이 보임.
- 목록 메타(`public.doc_posts`)는 이미 authenticated SELECT 정책만 있어 비공개 상태 → 본문만 비공개로 옮기면 됨.

## 2. 목표 구조

```
[로그인 사용자] → 게시글 클릭 → doc_posts.file 조회
   → supabase.storage.from('docs').createSignedUrl(path, 600)
   → 서명 URL(10분 유효)을 iframe src로 표시
[비로그인/직접 URL] → 버킷 private → 403/400, 열람 불가
```

- 버킷: `docs` (private, public=false)
- 객체 경로: `<scope>/<file>` (예: `personal/eia-assessor-written-exam-100-2026-09-25.html`, `company/asm-design-guide-ascendo-bi.html`)
- `doc_posts.file`은 파일명 그대로 유지, 경로는 `scope/file`로 조합 (DB 스키마 변경 최소화)

## 3. 작업 전 조사 (먼저 수행하고 결과를 보고)

1. 자료실 목록/상세 화면 컴포넌트와 라우트 찾기: `grep -rn "doc_posts\|seo-docs\|/docs/" src/`
2. iframe src를 만드는 코드 위치, `import.meta.env.BASE_URL` 사용 여부 확인
3. Supabase 클라이언트 위치(`src/lib/supabase.ts` 등)와 인증 방식 확인
   - 로그인(이메일+비밀번호, Supabase Auth)이 **Supabase Auth 세션(authenticated role)**을 만드는지 반드시 확인. `scripts/create_auth_users.mjs` 참고.
   - 세션이 없다면 Storage RLS가 동작하지 않으므로 방식 재검토 후 보고(대안: Edge Function이 자격 검증 후 서명 URL 발급).
4. `public/docs/` 파일 목록과 `doc_posts` 전체 행 대조(누락·고아 파일 확인)
5. "새 탭에서 열기" 링크, 문서 간 상호 링크(`/asuraDB/docs/...`), 문서 내 상대경로 이미지 사용 여부 확인

조사 결과를 요약해 보고하고 승인 후 4절 진행.

## 4. 구현 단계

### 4-1. Storage 버킷 + RLS (SQL은 `supabase/migrations/storage_docs_private.sql`로 기록, `supabase db push` 사용 금지 → SQL Editor 또는 service key로 적용)

```sql
insert into storage.buckets (id, name, public)
values ('docs', 'docs', false)
on conflict (id) do update set public = false;

create policy "docs read for authenticated"
on storage.objects for select
to authenticated
using (bucket_id = 'docs');
-- insert/update/delete 정책은 만들지 않음 (업로드는 service key 전용)
```

### 4-2. 기존 문서 이전 스크립트 `scripts/migrate_docs_to_storage.mjs`

- `.env`의 `SUPABASE_URL`, `SUPABASE_SERVICE_KEY` 사용(`scripts/_env.mjs` 재사용). 키를 출력·커밋하지 않는다.
- `doc_posts` 전체 조회 → 각 행의 `public/docs/<file>`을 `docs/<scope>/<file>`로 업로드(`contentType: 'text/html; charset=utf-8'`, `upsert: true`).
- 업로드 후 각 객체를 service key로 다운로드해 바이트 크기 일치 검증, 결과 표 출력.
- 이미지·CSS 등 부속 파일이 있으면 같은 경로에 함께 올린다.

### 4-3. 화면 코드 수정

- 상세 화면에서 iframe src를 `createSignedUrl('<scope>/<file>', 600)` 결과로 교체. 로딩·오류 상태 표시(만료/권한 없음 시 "다시 로그인" 안내).
- "새 탭에서 열기"도 서명 URL로 열기(새로 발급).
- iframe에 `sandbox="allow-same-origin allow-scripts allow-popups"` 검토(문서 내 앵커 목차 동작 확인).
- 서명 URL은 캐시하지 말고 열 때마다 발급(또는 만료 1분 전 재발급).
- **주의**: Supabase Storage는 HTML을 `text/plain`으로 내려줄 수 있음. iframe에서 HTML이 렌더링되지 않고 소스로 보이면, 서명 URL로 `fetch` → `text()` → `iframe.srcdoc`에 주입하는 방식으로 전환한다(문서는 자체 완결형 HTML이라 srcdoc로 동작). 이 경우 목차 앵커(`#s1`)가 srcdoc 안에서 동작하는지 확인.

### 4-4. 공개 경로 제거

- `public/docs/*.html`을 저장소에서 삭제(`git rm`). 로컬 백업은 `~/asuraDB-docs-backup-YYYYMMDD/`에 복사 후 진행.
- 배포 후 gh-pages 브랜치에 `docs/`가 남지 않는지 확인.
- `vite.config`·빌드 스크립트가 `public/docs`를 참조하면 제거.

### 4-5. 업로드 절차 갱신

- `scripts/register-doc.sh`(또는 새 `scripts/upload-doc.mjs`)를 "Storage 업로드 + doc_posts insert" 한 번에 하도록 변경. 사용법:
  `node scripts/upload-doc.mjs <scope> "<title>" "<category>" <YYYY-MM-DD> <local.html>`
- `docs/AsuraDB_Development_Guide.md` §11(연결/보안)에 비공개 문서 구조 추가.
- `docs/웹사이트_운영_변경이력.md`에 `### 2026-10-XX — 자료실 문서 비공개 전환(Supabase Storage)` 항목 추가.

## 5. 검증 체크리스트 (모두 통과해야 완료)

- [ ] 로그인 후 `#/seo-docs`, `#/docs` 모든 글이 iframe에 정상 렌더링(한글·표·목차 앵커 포함)
- [ ] "새 탭에서 열기" 동작
- [ ] 로그아웃 상태에서 상세 화면 접근 시 문서 미표시
- [ ] `curl -s -o /dev/null -w "%{http_code}" https://hungaseo-arch.github.io/asuraDB/docs/<기존파일>.html` → 404
- [ ] anon key로 `storage/v1/object/public/docs/...` 및 `object/docs/...` 접근 → 실패(400/403)
- [ ] 서명 URL 10분 후 만료 확인
- [ ] `npm run type-check`, `npm run build` 통과
- [ ] 이전 스크립트 결과: doc_posts 행 수 = 업로드 객체 수, 크기 일치

## 6. 후속(사용자 결정 사항, 이번 작업 범위 아님)

- 저장소 private 전환: GitHub Free는 private 저장소로 Pages 불가 → Cloudflare Pages 등으로 호스팅 이전 필요. 진행 여부는 별도 결정.
- 이미 공개됐던 문서는 git 히스토리에 남음. 완전 삭제가 필요하면 `git filter-repo`로 `public/docs` 히스토리 제거 + force push(위험, 별도 승인).

## 7. 규칙

- 단계별로 커밋(`feat: docs storage bucket`, `feat: signed url viewer`, `chore: migrate docs`, `chore: remove public docs`).
- service key, 비밀번호, 개인정보를 코드·로그·커밋에 남기지 않는다.
- 4-4(공개 파일 삭제)는 4-3 검증이 끝난 뒤에만 진행.
- 막히는 지점(특히 3-3 인증 방식)은 임의로 우회하지 말고 보고 후 결정받는다.

---

### VS Code 클로드에게 줄 첫 메시지

```
docs/작업지시서_문서비공개전환_SupabaseStorage.md를 읽고 3절 "작업 전 조사"만 먼저 수행해서 결과를 보고해줘. 승인 전에는 코드를 수정하지 마.
```
