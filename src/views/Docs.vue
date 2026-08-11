<script setup lang="ts">
import { ref, computed, watch, onMounted, nextTick } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { FileText, ArrowLeft, ChevronLeft, ChevronRight, Search } from 'lucide-vue-next';
import PageHeader from '@/components/PageHeader.vue';
import TableState from '@/components/ui/TableState.vue';
import { sbGet } from '@/lib/supabase';
import { errMsg } from '@/lib/utils';

interface Post {
  id: number;
  title: string;
  category: string;
  date: string;           // 등록일 YYYY-MM-DD
  updated: string | null; // 수정일 YYYY-MM-DD (수정 이력 없으면 null)
  file: string;           // public/docs/*.html
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
const docSrc = (p: Post) => `${import.meta.env.BASE_URL}docs/${p.file}`;
function open(p: Post) { selected.value = p; }
function back() { selected.value = null; }

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
        <a
          :href="docSrc(selected)" target="_blank" rel="noopener noreferrer"
          class="text-xs text-primary hover:text-primary/80 font-medium"
        >새 탭에서 열기 ↗</a>
      </div>
      <div class="rounded-xl border border-border bg-card overflow-hidden">
        <div class="px-5 py-3 border-b border-border bg-muted/20">
          <h2 class="text-sm font-bold text-foreground">{{ selected.title }}</h2>
          <p class="text-[11px] text-muted-foreground mt-0.5">
            {{ selected.category }} · 등록일 {{ selected.date }}
            <span v-if="selected.updated"> · 수정일 {{ selected.updated }}</span>
          </p>
        </div>
        <iframe
          :src="docSrc(selected)"
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
