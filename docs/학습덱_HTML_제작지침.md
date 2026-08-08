# 학습덱 HTML 제작 지침 (public/docs/)

`public/docs/` 에 넣는 **학습용 정적 HTML 덱**(영어학습 등)의 표준 규격이다.
**신규 덱을 추가하거나 기존 덱을 수정할 때는 이 문서를 그대로 따른다.** 눈대중으로 새 디자인을 만들지 않는다.

- **기준본(레퍼런스)**: [`public/docs/phrasal-verbs-deck-200.html`](../public/docs/phrasal-verbs-deck-200.html)
  → 새 덱은 **이 파일을 복사해서 데이터만 갈아끼우는 것**이 가장 안전하고 빠르다.
- 2026-08-03 기준 이 규격을 따르는 덱: `phrasal-verbs-deck-200.html` · `phrasal-verbs-deck-200-v2.html` ·
  `light-verbs-deck-200.html` · `sentence-openers-30.html` · `daily-english-100.html`

---

## 0. 절대 규칙 5가지

1. **라이트 모드 고정** — `:root` 는 아래 §2 토큰 블록을 그대로 쓴다. 하드코딩 색(`#fff`, 다크 배경) 금지.
2. **3개 언어 세트 필수** — 표제어/문장은 **영어 · 인도네시아어 · 한국어** 3종을 항상 채운다.
   특히 **예문에는 인니어 예문이 반드시 있어야 한다**(§4 데이터 스키마 `id_ex`). 비워 두지 않는다.
3. **목록 카드는 3칸 레이아웃** — `.nbox`(번호) / `.wbox`(표제어) / `.ex`(예문). §3 CSS 를 그대로 복사.
4. **🔊 듣기 버튼은 문장에만** — 영어 예문 `en-US`, 인니어 예문 `id-ID`. 뜻풀이(단어 뜻)에는 달지 않는다.
   (예외: 표제어 자체가 문장인 덱 — `daily-english-100` — 은 표제어에 단다.)
5. **작업 후 변경이력 기록** — [`docs/웹사이트_운영_변경이력.md`](웹사이트_운영_변경이력.md) 맨 위에 항목 추가
   (루트 `CLAUDE.md` 의 필수 지침).

---

## 1. 파일·게시판 등록

| 항목 | 규칙 |
|---|---|
| 파일 위치 | `public/docs/<슬러그>.html` — 슬러그는 kebab-case, 개수를 붙인다 (`light-verbs-deck-200.html`) |
| 인코딩 | UTF-8, `<html lang="ko">`, `<meta name="viewport" content="width=device-width, initial-scale=1">` |
| 제목 | `<title>` 은 게시판 제목과 **문자 그대로 일치**시킨다 |
| 게시판 등록 | `doc_posts` 에 insert. `scope`(`company`/`personal`) · `category` · `published_on`(등록일) · `file`(UNIQUE) |
| 수정 시 | 본문을 고쳤으면 `doc_posts.updated_on` 을 그날 날짜로 갱신 (게시판 '수정일' 열) |
| 마이그레이션 | `supabase/migrations/` 에 `on conflict (file) do nothing` 형태의 멱등 SQL 로 남긴다 |

```sql
insert into public.doc_posts (scope, title, category, published_on, file)
values ('personal', '<title 과 동일>', '영어학습', 'YYYY-MM-DD', '<슬러그>.html')
on conflict (file) do nothing;
```

---

## 2. 색 토큰 (`:root`) — 그대로 복사

앱(`src/style.css`)의 시맨틱 토큰과 1:1로 맞춘 값이다. **수정 금지, 그대로 붙여넣는다.**

```css
:root{
  color-scheme:light;
  /* AsuraDB 앱 시맨틱 토큰 (src/style.css 와 1:1) */
  --background:oklch(0.99 0.002 260); --foreground:oklch(0.15 0.01 260);
  --card:oklch(0.98 0.003 260);
  --primary:oklch(0.45 0.18 260); --primary-foreground:oklch(0.98 0.003 260);
  --muted:oklch(0.94 0.008 260); --muted-foreground:oklch(0.48 0.02 260);
  --border:oklch(0.88 0.01 260);
  /* 기존 변수 → 앱 토큰 별칭 */
  --grey:var(--background);
  --bluegrey:var(--muted);
  --blue:color-mix(in oklch, var(--primary) 12%, var(--card));
  --sage:color-mix(in oklch, var(--primary) 9%, var(--card));
  --ink:var(--muted-foreground);
  --ink-strong:var(--foreground);
  --line:var(--border);
}
```

**선택 상태(탭·칩)는 `--primary` 틴트 하나로 통일**한다:

```css
.tab[aria-selected="true"],
.chip[aria-pressed="true"]{
  background:color-mix(in oklch,var(--primary) 15%,transparent);
  color:var(--primary);
  border-color:color-mix(in oklch,var(--primary) 35%,var(--line));
}
.dot[aria-current="true"]{background:var(--primary);transform:scale(1.35)}
```

기타 고정값: 컨테이너 `.wrap{max-width:820px;margin:0 auto;padding:0 16px 56px}` ·
검색 입력 `font-size:16px`(**iOS 자동 확대 방지 — 15px 이하 금지**).

---

## 3. 목록 카드 3칸 레이아웃 — 그대로 복사

```css
.lcard{background:var(--card);border:1px solid var(--line);border-left:4px solid var(--primary);border-radius:12px;padding:10px 12px;margin-bottom:8px;
  display:flex;gap:10px;align-items:stretch;flex-wrap:wrap}
/* 1칸: 숫자 박스 */
.nbox{flex:0 0 auto;width:48px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;
  background:var(--bluegrey);border-radius:8px;padding:6px}
.idx{font-size:14px;font-weight:700;color:var(--ink);font-variant-numeric:tabular-nums}
/* 2칸: 표제어 박스 (영어 · 인니어뜻 · 한국어뜻) */
.wbox{flex:1 1 180px;min-width:160px;max-width:280px;display:flex;flex-direction:column;justify-content:center;gap:4px;
  background:var(--blue);border-radius:8px;padding:9px 12px;overflow-wrap:break-word}
.v{font-size:17px;font-weight:700;letter-spacing:-.01em}
.ko{font-size:13.5px;font-weight:600}
.id{font-size:12.5px;color:var(--ink)}
/* 3칸: 예문 박스 */
.ex{flex:2 1 300px;min-width:220px;margin:0;padding:10px 12px;background:var(--bluegrey);border-radius:8px;
  display:flex;flex-direction:column;justify-content:center;overflow-wrap:break-word}
.ex .en{margin:0;font-size:14px}
.ex .idex{margin:4px 0 0;font-size:12.5px;color:var(--ink-strong)}
.ex .kr{margin:3px 0 0;font-size:12.5px;color:var(--ink)}
```

**칸 안의 순서(고정)**

| 칸 | 내용 순서 |
|---|---|
| `.nbox` | 번호 → (있으면) 작은 배지 1개 |
| `.wbox` | `.v` 영어 표제어 → `.id` 인니어 뜻 → `.ko` 한국어 뜻 |
| `.ex`   | `.en` 영어 예문 🔊 → `.idex` 인니어 예문 🔊 → `.kr` 한국어 번역 |

**덱별 부가 필드는 새 칸을 만들지 말고 위 3칸 안에 넣는다.**
예) 문서유형 배지 → `.nbox` / 단일동사 대체어 → `.wbox` / 형태 배지 → `.v` 옆 / 실무 주의 → `.ex` 안.

렌더 템플릿(기준본과 동일):

```js
html+='<article class="lcard">'
  +'<div class="nbox"><span class="idx">'+d[IDX]+'</span></div>'
  +'<div class="wbox">'
    +'<span class="v">'+esc(d.en)+'</span>'
    +'<span class="id">'+esc(d.id)+'</span>'
    +'<span class="ko">'+esc(d.ko)+'</span>'
  +'</div>'
  +'<div class="ex">'
    +'<p class="en"><span>'+esc(d.en_ex)+'</span><button class="say" type="button" data-lang="en-US" data-say="'+esc(d.en_ex)+'" aria-label="영어 예문 듣기">🔊</button></p>'
    +'<p class="idex"><span class="idtx">'+esc(d.id_ex)+'</span><button class="say" type="button" data-lang="id-ID" data-say="'+esc(d.id_ex)+'" aria-label="인니어 예문 듣기">🔊</button></p>'
    +'<p class="kr">'+esc(d.ko_ex)+'</p>'
  +'</div></article>';
```

---

## 4. DATA 스키마

목록 데이터는 **배열의 배열**이고, 아래 6개는 **필수**다(순서는 덱마다 달라도 되나 누락 금지).

| 키 | 뜻 | 예 |
|---|---|---|
| `group` | 분류(칩 필터 키) | `"up"`, `"make"`, `"의도·계획"` |
| `en` | 영어 표제어 | `"add up"` |
| `ko` | 한국어 뜻 | `"앞뒤가 맞다, 합산되다"` |
| `id` | 인니어 뜻 | `"masuk akal; menjumlahkan"` |
| `en_ex` | 영어 예문 | `"The figures in this invoice don't add up."` |
| `ko_ex` | 한국어 번역 | `"이 인보이스의 숫자가 맞지 않습니다."` |
| **`id_ex`** | **인니어 예문 — 필수** | `"Angka-angka di faktur ini tidak cocok."` |

주의사항:

- 화면 번호는 데이터에 넣지 않는다. 로드 직후 `DATA.forEach((d,i)=>d.push(i+1));` 로 **런타임에 뒤에 붙인다.**
  → **새 필드를 배열 끝에 추가하면 번호 인덱스가 한 칸 밀린다.** 렌더/검색 코드의 인덱스를 함께 고쳐야 한다.
- 검색 필터에는 **인니어 예문도 포함**시킨다: `(d[1]+' '+d[2]+' '+…+' '+d[id_ex]).toLowerCase().includes(q)`
- 예문의 숫자·통화는 앱 전체 표기(영미식 콤마/마침표)를 따른다 — `USD 84.25/EA`, `IDR 1,250,000,000 (1.25 miliar)`.
- 인니어 문장은 실무 무역 문어체로 쓴다. `L/C · B/L · forwarder · booking · demurrage` 같은 업계어는 그대로 둔다.

---

## 5. 🔊 듣기 버튼 (Web Speech API)

**규칙**: 문장에만 단다(영어 예문 `en-US`, 인니어 예문 `id-ID`). 단어 뜻에는 달지 않는다.
표제어가 문장인 덱만 표제어에 단다.

```css
.say{border:none;background:var(--sage);color:var(--ink-strong);border-radius:5px;
  width:24px;height:20px;font-size:11px;line-height:1;padding:0;margin-left:7px;
  cursor:pointer;vertical-align:1px;font-family:inherit}
.say:hover{filter:brightness(.96)}
.say:active{transform:scale(.9)}
.say.playing{background:var(--primary);color:var(--primary-foreground)}
.say:focus-visible{outline:2px solid var(--ink);outline-offset:2px}
```

```js
/* ===================== 음성 읽기 (Web Speech API) ===================== */
let sayBtn=null;
// 표준 성별 속성이 없어 이름 기반으로 여성 보이스 우선 선택 (영어 TTS 여성 지정용)
const FEMALE_EN=/\b(samantha|victoria|allison|ava|susan|zoe|nicky|karen|moira|tessa|fiona|serena|kate|female|zira|aria|jenny|catherine|libby|sonia|michelle|clara|google us english|google uk english female)\b/i;
function pickVoice(vs,lang,female){ /* 기준본 그대로 */ }
function speak(btn){ /* 같은 버튼 재클릭 = 정지(토글), 재생 중 .playing */ }
if(window.speechSynthesis){window.speechSynthesis.getVoices();window.speechSynthesis.onvoiceschanged=()=>window.speechSynthesis.getVoices()}

listEl.addEventListener('click',e=>{
  const s=e.target.closest('.say');
  if(s){e.stopPropagation();speak(s);return}   // ← 반드시 목록 클릭 핸들러 '맨 위'
  …
});
```

- 클릭 위임은 **목록 컨테이너 한 곳**에만 건다(카드마다 리스너 금지).
- `.say` 처리는 다른 클릭 처리보다 **먼저** 하고 `stopPropagation()` — 학습 모드에서 버튼이 '뜻 까기'로 새지 않게.

---

## 6. 학습(뜻 가리기) 모드

가리는 대상은 **뜻·번역**이다. 영어/인니어 **예문 본문은 가리지 않는다**(듣기 학습용).

```css
body.study .ko, body.study .id, body.study .ex .kr, body.study .idtx{
  background:var(--ink);color:transparent;border-radius:4px;user-select:none;cursor:pointer}
body.study .revealed{background:transparent!important;color:inherit!important;cursor:auto}
```

```js
const t=e.target.closest('.ko,.id,.kr,.idtx');
if(t)t.classList.toggle('revealed');
```

- 마스킹 대상 텍스트는 **`<span class="idtx">` 처럼 텍스트만 감싼다.** 🔊 버튼이 마스크 안에 들어가면 안 된다.
- 표제어가 문장인 덱(`daily-english-100`)은 인니어 문장이 '뜻' 역할이므로 `.idtx` 를 마스킹 대상에 넣는다.

---

## 7. 반응형 (아이폰 portrait ~430px 커버)

```css
@media (max-width:560px){
  .wrap{padding:0 14px 48px}
  header{padding:18px 0 10px}
  h1{font-size:21px}
  .card{min-height:445px}          /* 덱별 카드 높이는 각자 값 유지 */
  /* 목록 카드: [번호 + 표제어] 한 줄 → [예문] 아랫줄로 접힘 */
  .lcard{gap:8px}
  .nbox{width:40px}
  .wbox{flex:1 1 auto;min-width:0;max-width:none}
  .ex{flex:1 1 100%;min-width:0}
  .say{width:30px;height:24px;font-size:12px}   /* 🔊 탭 영역 확대 */
}
@media (max-width:380px){
  .tab{padding:10px 6px;font-size:12.5px}
  .v{font-size:16px}
}
```

탭이 4개 이상이면 `560px` 블록에 `.tab{font-size:12px;padding:10px 5px}` 정도를 덧붙인다.

---

## 8. 완료 체크리스트

새 덱을 추가했거나 기존 덱을 고쳤으면 아래를 전부 확인한다.

- [ ] `:root` 토큰 블록이 §2 와 **글자 그대로** 같다 (하드코딩 색 없음)
- [ ] 목록 카드가 `.nbox`/`.wbox`/`.ex` 3칸이고 칸 안 순서가 §3 표와 같다
- [ ] **모든 행에 인니어 예문(`id_ex`)이 있다** — 빈 문자열 0건
- [ ] 🔊 가 영어 예문·인니어 예문에만 붙었고, 같은 버튼 재클릭 시 정지된다
- [ ] 학습 모드에서 뜻·번역만 가려지고 🔊 버튼은 가려지지 않는다
- [ ] 검색이 인니어 예문까지 걸린다
- [ ] 데이터 필드를 추가했다면 **런타임 번호 인덱스(`d[n]`)를 렌더·검색에서 모두 맞췄다**
- [ ] 폭 390px 에서 카드가 2줄로 접히고 가로 스크롤이 생기지 않는다
- [ ] `doc_posts` 등록(신규) 또는 `updated_on` 갱신(수정) 완료
- [ ] `docs/웹사이트_운영_변경이력.md` 에 항목 추가

빠른 확인용(헤드리스 렌더):

```bash
cd public/docs
{ cat <파일>.html; echo '<script>showPanel("list")</script>'; } > /tmp/shot.html
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu \
  --screenshot=/tmp/shot.png --window-size=900,900 --virtual-time-budget=3000 file:///tmp/shot.html
```
