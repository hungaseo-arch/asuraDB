<script setup lang="ts">
import { ref, computed, watch, onMounted, onBeforeUnmount, nextTick } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { FileText, ArrowLeft, ChevronLeft, ChevronRight, Search } from 'lucide-vue-next';
import PageHeader from '@/components/PageHeader.vue';
import TableState from '@/components/ui/TableState.vue';
import { sbGet, sbRpc, supabase } from '@/lib/supabase';
import { errMsg } from '@/lib/utils';

interface Post {
  id: number;
  title: string;
  category: string;
  date: string;           // 등록일 YYYY-MM-DD
  updated: string | null; // 수정일 YYYY-MM-DD (수정 이력 없으면 null)
  file: string;           // Storage docs/<scope>/<file>
}

// 이 게시판은 '정리'(회사 자료)와 'SEO자료'(개인 자료실)가 공유한다.
// 라우트 meta.scope 로 목록만 갈라 본다 (DB: doc_posts.scope).
const route = useRoute();
const scope = computed<'company' | 'personal'>(
  () => (route.meta.scope === 'personal' ? 'personal' : 'company'),
);
const subtitle = computed(() =>
  scope.value === 'personal' ? '개인 자료·참고 문서 모음 · 게시판' : '회사 자료·검토 문서 모음 · 게시판',
);

// DB(doc_posts) 미적용 환경 폴백용 기본 목록 — 회사 자료(scope=company)에만 해당
const DEFAULT_POSTS: Post[] = [
  { id: 3, title: '인도네시아 타이어 수입 분석 보고서 · 2026', category: '수입 분석', date: '2026-07-22', updated: null, file: 'tire_import_report_2026.html' },
  { id: 2, title: '타이어 원가 시뮬레이션', category: '원가 분석', date: '2026-07-03', updated: null, file: 'asuradb_tire_cost_simulation.html' },
  { id: 1, title: '재고·Buffer Stock 적정성 검토 산식 작성 가이드', category: '재고량 산정', date: '2026-06-25', updated: null, file: 'buffer_stock_review.html' },
];

const posts = ref<Post[]>([]);
const loading = ref(true);
const loadError = ref<string | null>(null);

interface DocRow { id: number; title: string; category: string; published_on: string; updated_on: string | null; file: string }

async function loadPosts() {
  loading.value = true;
  loadError.value = null;
  const isPersonal = scope.value === 'personal';
  try {
    const rows = await sbGet<DocRow[]>(
      `doc_posts?select=id,title,category,published_on,updated_on,file&scope=eq.${scope.value}&order=published_on.desc`,
    );
    posts.value = rows?.length
      ? rows.map(r => ({
          id: r.id, title: r.title, category: r.category,
          date: r.published_on, file: r.file,
          // 수정일 == 등록일 은 '수정 이력 없음' 과 같은 뜻 → null 로 눕혀 '—' 로 표기
          updated: r.updated_on && r.updated_on !== r.published_on ? r.updated_on : null,
        }))
      // 개인 자료실은 아직 문서가 없을 수 있다 — 회사 문서를 섞어 보여주면 안 되므로 빈 목록 유지
      : (isPersonal ? [] : DEFAULT_POSTS);
  } catch (e) {
    // 회사 자료는 정적 기본 목록으로 폴백 가능 → 그대로 보여준다.
    // 개인 자료실은 폴백이 없으므로 실패를 숨기지 않고 사유 + 재시도를 노출한다.
    posts.value = isPersonal ? [] : DEFAULT_POSTS;
    if (isPersonal) loadError.value = errMsg(e);
  }
  loading.value = false;
}
onMounted(loadPosts);

// ── 검색 · 분류 필터 ──────────────────────────────────────────────────────────
const query = ref('');
const category = ref('전체');

const filtered = computed(() => {
  const q = query.value.trim().toLowerCase();
  return posts.value
    .filter(p => category.value === '전체' || p.category === category.value)
    .filter(p => !q || p.title.toLowerCase().includes(q) || p.category.toLowerCase().includes(q))
    .sort((a, b) => b.date.localeCompare(a.date));
});

// ── 페이지네이션 ──────────────────────────────────────────────────────────────
const PAGE_SIZE = 10;
const page = ref(1);
const totalPages = computed(() => Math.max(1, Math.ceil(filtered.value.length / PAGE_SIZE)));
const paged = computed(() => filtered.value.slice((page.value - 1) * PAGE_SIZE, page.value * PAGE_SIZE));
const rowNo = (idx: number) => filtered.value.length - ((page.value - 1) * PAGE_SIZE + idx);
// 검색·분류 변경 시 1페이지로
watch([query, category], () => { page.value = 1; });

// ── URL 쿼리 동기화 (?q=&page=) ───────────────────────────────────────────────
// 검색어·페이지를 주소에 실어 새로고침·뒤로가기에서 유지하고, 검색 결과 링크를 공유할 수 있게 한다.
const router = useRouter();
const qs = (v: unknown) => (typeof v === 'string' ? v : undefined);
const isBoard = () => route.name === 'docs' || route.name === 'seo-docs';

watch([query, page], () => {
  const next: Record<string, string> = {};
  const kw = query.value.trim();
  if (kw) next.q = kw;
  if (page.value > 1) next.page = String(page.value);
  if ((next.q ?? '') === (qs(route.query.q) ?? '') && (next.page ?? '') === (qs(route.query.page) ?? '')) return;
  void router.replace({ query: next });
});

function applyQuery(rq: typeof route.query) {
  const kw = qs(rq.q) ?? '';
  if (kw !== query.value) query.value = kw;
  const n = Math.max(1, Number(qs(rq.page) ?? 1) || 1);
  // 검색어 변경 watch 가 page 를 1 로 되돌리므로 그 뒤(다음 tick)에 적용한다
  void nextTick(() => { if (page.value !== n) page.value = n; });
}
watch(() => route.query, rq => { if (isBoard()) applyQuery(rq); });
applyQuery(route.query);   // 첫 진입 — 주소에 담긴 상태 복원

// ── 문서 뷰어 ────────────────────────────────────────────────────────────────
const selected = ref<Post | null>(null);
// 본문 HTML 은 private 버킷 `docs/<scope>/<file>` 에 있다 → 서명 URL(10분)로 받아 srcdoc 로 주입한다.
//   (Storage 는 HTML 을 text/plain 으로 내릴 수 있어 iframe src 직결 대신 fetch → srcdoc. 동일 출처가 돼 브리지도 유지)
const docHtml = ref<string | null>(null);
const docLoading = ref(false);
const docError = ref<string | null>(null);
let docReq = 0;   // 빠르게 다른 글을 열 때 늦게 도착한 응답을 버리기 위한 토큰

// srcdoc 에서는 `#id` 앵커 이동이 보장되지 않아, 목차 클릭을 scrollIntoView 로 대신 처리한다.
const ANCHOR_FIX = `<script>document.addEventListener('click',function(e){var a=e.target.closest&&e.target.closest('a[href^="#"]');if(!a||a.getAttribute('href').length<2)return;var id=decodeURIComponent(a.getAttribute('href').slice(1));var t=document.getElementById(id)||document.getElementsByName(id)[0];if(t){e.preventDefault();t.scrollIntoView({behavior:'smooth',block:'start'});}});<\/script>`;
const withAnchorFix = (html: string) =>
  /<\/body>/i.test(html) ? html.replace(/<\/body>(?![\s\S]*<\/body>)/i, () => `${ANCHOR_FIX}</body>`) : html + ANCHOR_FIX;

async function fetchDoc(p: Post): Promise<string> {
  // 서명 URL 은 캐시하지 않고 열 때마다 발급한다
  const { data, error } = await supabase.storage.from('docs').createSignedUrl(`${scope.value}/${p.file}`, 600);
  if (error || !data?.signedUrl) throw new Error('열람 권한이 없거나 로그인 세션이 만료되었습니다. 다시 로그인해 주세요.');
  const res = await fetch(data.signedUrl);
  if (!res.ok) throw new Error(`문서를 불러오지 못했습니다 (${res.status}).`);
  return res.text();
}

async function open(p: Post) {
  selected.value = p;
  docHtml.value = null;
  docError.value = null;
  docLoading.value = true;
  const req = ++docReq;
  try {
    const html = await fetchDoc(p);
    if (req === docReq) docHtml.value = withAnchorFix(html);
  } catch (e) {
    if (req === docReq) docError.value = errMsg(e);
  } finally {
    if (req === docReq) docLoading.value = false;
  }
}
function back() { docReq++; selected.value = null; docHtml.value = null; docError.value = null; }

// 받아온 HTML 로 Blob URL 을 만들어 새 탭에서 연다 (Storage URL 을 직접 열지 않음)
function openInNewTab() {
  if (docHtml.value == null) return;
  const url = URL.createObjectURL(new Blob([docHtml.value], { type: 'text/html;charset=utf-8' }));
  window.open(url, '_blank', 'noopener');
  setTimeout(() => URL.revokeObjectURL(url), 60_000);
}

// ── 문항 열람 기록 브리지 ─────────────────────────────────────────────────────
// 정적 HTML(iframe, 동일 출처)은 로그인 세션이 없으므로 postMessage 로 뷰어에 위임한다.
//   iframe → { type:'doc-views-ready' } | { type:'doc-view', q }   (같은 출처만 수락)
//   뷰어   → { type:'doc-views', views:{ [q]: {count, first, last} } }
interface ViewRow { q_no: number; view_count: number; first_viewed_at: string; last_viewed_at: string }
const docFrame = ref<HTMLIFrameElement | null>(null);

function postViews(rows: ViewRow[]) {
  const views: Record<number, { count: number; first: string; last: string }> = {};
  for (const r of rows) views[r.q_no] = { count: r.view_count, first: r.first_viewed_at, last: r.last_viewed_at };
  docFrame.value?.contentWindow?.postMessage({ type: 'doc-views', views }, window.location.origin);
}
async function onDocMessage(e: MessageEvent) {
  if (e.origin !== window.location.origin || e.source !== docFrame.value?.contentWindow) return;
  const file = selected.value?.file;
  const d = e.data as { type?: string; q?: number } | null;
  if (!file || !d) return;
  try {
    if (d.type === 'doc-views-ready') {
      postViews(await sbGet<ViewRow[]>(`doc_question_views?file=eq.${encodeURIComponent(file)}&select=q_no,view_count,first_viewed_at,last_viewed_at`));
    } else if (d.type === 'doc-view' && Number.isInteger(d.q)) {
      const row = await sbRpc<ViewRow>('record_doc_view', { p_file: file, p_q: d.q });
      docFrame.value?.contentWindow?.postMessage(
        { type: 'doc-views', views: { [row.q_no]: { count: row.view_count, first: row.first_viewed_at, last: row.last_viewed_at } } },
        window.location.origin,
      );
    }
  } catch { /* 기록 실패는 열람에 영향 없음(테이블 미적용 환경 등) */ }
}
onMounted(() => window.addEventListener('message', onDocMessage));
onBeforeUnmount(() => window.removeEventListener('message', onDocMessage));

// '정리' ↔ 'SEO자료' 는 같은 컴포넌트를 재사용하므로 라우트만 바뀌면 재조회해야 한다
watch(scope, () => {
  selected.value = null;
  page.value = 1;
  void loadPosts();
});
</script>

<template>
  <div class="p-4 sm:p-5 space-y-4 max-w-300 mx-auto">
    <PageHeader>
      <template #subtitle>
        <p class="text-xs text-muted-foreground">{{ subtitle }}</p>
      </template>
      <template #controls>
        <div v-if="!selected" class="flex items-center gap-2 self-end">
          <div class="relative">
            <Search :size="14" class="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
            <input
              v-model="query"
              type="text"
              placeholder="제목 검색…"
              class="w-48 bg-card border border-border rounded-lg pl-8 pr-3 py-2 text-xs text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary"
            />
          </div>
        </div>
      </template>
    </PageHeader>

    <!-- 상세: 문서 뷰어 -->
    <div v-if="selected" class="space-y-3">
      <div class="flex items-center justify-between">
        <button
          class="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground transition-colors"
          @click="back"
        >
          <ArrowLeft :size="16" /> 목록
        </button>
        <button
          :disabled="docHtml == null"
          class="text-xs text-primary hover:text-primary/80 font-medium disabled:opacity-40 disabled:cursor-not-allowed"
          @click="openInNewTab"
        >새 탭에서 열기 ↗</button>
      </div>
      <div class="rounded-xl border border-border bg-card overflow-hidden">
        <div class="px-5 py-3 border-b border-border bg-muted/20">
          <h2 class="text-sm font-bold text-foreground">{{ selected.title }}</h2>
          <p class="text-[11px] text-muted-foreground mt-0.5">
            {{ selected.category }} · 등록일 {{ selected.date }}
            <span v-if="selected.updated"> · 수정일 {{ selected.updated }}</span>
          </p>
        </div>
        <div v-if="docLoading" class="flex items-center justify-center text-sm text-muted-foreground" style="height: 40vh">
          문서를 불러오는 중…
        </div>
        <div v-else-if="docError" class="flex flex-col items-center justify-center gap-3 text-sm text-muted-foreground" style="height: 40vh">
          <p>{{ docError }}</p>
          <button class="text-xs text-primary font-medium" @click="open(selected)">다시 시도</button>
        </div>
        <iframe
          v-else-if="docHtml != null"
          ref="docFrame"
          :srcdoc="docHtml"
          sandbox="allow-same-origin allow-scripts allow-popups allow-popups-to-escape-sandbox"
          class="w-full bg-card block"
          style="height: calc(100vh - 220px)"
          title="문서 미리보기"
        />
      </div>
    </div>

    <!-- 목록: 게시판 -->
    <div v-else class="rounded-xl border border-border bg-card overflow-hidden">
      <div class="overflow-x-auto">
      <table class="w-full text-sm">
        <caption class="sr-only">자료실 게시글 목록</caption>
        <thead>
          <tr class="border-b border-border bg-muted/20 text-xs text-muted-foreground">
            <th scope="col" class="w-16 text-center font-semibold px-3 py-2.5">No.</th>
            <th scope="col" class="text-left font-semibold px-3 py-2.5">제목</th>
            <th scope="col" class="w-40 text-left font-semibold px-3 py-2.5 hidden sm:table-cell">분류</th>
            <th scope="col" class="w-28 text-right font-semibold px-3 py-2.5 hidden sm:table-cell">등록일</th>
            <th scope="col" class="w-28 text-right font-semibold px-3 py-2.5 hidden md:table-cell">수정일</th>
          </tr>
        </thead>
        <tbody>
          <TableState
            v-if="loading || loadError || !paged.length"
            :colspan="5" :loading="loading" :error="loadError" :skeleton-rows="6"
            :empty-text="query || category !== '전체'
              ? '검색 결과가 없습니다.'
              : (scope === 'personal' ? '등록된 개인 자료가 없습니다.' : '문서가 없습니다.')"
            @retry="loadPosts"
          />
          <tr
            v-for="(p, i) in paged"
            v-else
            :key="p.id"
            class="border-b border-border/50 last:border-b-0 hover:bg-accent/40 cursor-pointer transition-colors"
            @click="open(p)"
          >
            <td class="text-center text-muted-foreground tabular-nums px-3 py-3">{{ rowNo(i) }}</td>
            <td class="px-3 py-3">
              <div class="flex items-center gap-2 min-w-0">
                <FileText :size="15" class="text-primary shrink-0" />
                <span class="font-medium text-foreground truncate">{{ p.title }}</span>
              </div>
            </td>
            <td class="px-3 py-3 text-muted-foreground hidden sm:table-cell">{{ p.category }}</td>
            <td class="px-3 py-3 text-right text-muted-foreground tabular-nums hidden sm:table-cell">{{ p.date }}</td>
            <td class="px-3 py-3 text-right text-muted-foreground tabular-nums hidden md:table-cell">
              <span v-if="p.updated">{{ p.updated }}</span>
              <span v-else title="수정 이력 없음 (등록 후 변경되지 않음)" aria-label="수정 이력 없음">—</span>
            </td>
          </tr>
        </tbody>
      </table>
      </div>

      <!-- 페이지네이션 -->
      <div v-if="!loading && !loadError && paged.length" class="flex items-center justify-center gap-1 py-3 border-t border-border">
        <button
          :disabled="page <= 1"
          class="inline-flex items-center justify-center h-8 w-8 rounded-md border border-border text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
          @click="page--"
        >
          <ChevronLeft :size="16" />
        </button>
        <button
          v-for="n in totalPages"
          :key="n"
          :class="['h-8 min-w-8 px-2 rounded-md text-sm border transition-colors',
            n === page ? 'bg-primary/15 text-primary border-primary/30 font-semibold' : 'border-border text-muted-foreground hover:bg-accent']"
          @click="page = n"
        >
          {{ n }}
        </button>
        <button
          :disabled="page >= totalPages"
          class="inline-flex items-center justify-center h-8 w-8 rounded-md border border-border text-muted-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
          @click="page++"
        >
          <ChevronRight :size="16" />
        </button>
      </div>
    </div>
  </div>
</template>
