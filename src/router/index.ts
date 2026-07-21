import { createRouter, createWebHashHistory, type RouteRecordRaw } from 'vue-router';
import Layout from '@/components/Layout.vue';
import { supabase } from '@/lib/supabase';
import { syncRoleFromSession } from '@/lib/auth';
import { pushRecent } from '@/lib/recent';

const routes: RouteRecordRaw[] = [
  {
    path: '/',
    component: Layout,
    children: [
      {
        path: '',
        redirect: '/home',
      },
      {
        path: 'home',
        name: 'home',
        component: () => import('@/views/Home.vue'),
        meta: { title: '홈' },
      },
      {
        path: 'search',
        name: 'search',
        component: () => import('@/views/Search.vue'),
        meta: { title: '로컬 검색' },
      },
      {
        path: 'ai-search',
        name: 'ai-search',
        component: () => import('@/views/AiSearch.vue'),
        meta: { title: 'AI 지식 Q&A' },
      },
      {
        path: 'quote',
        name: 'quote',
        component: () => import('@/views/Quote.vue'),
        meta: { title: '견적서 작성' },
      },
      {
        path: 'price-compare',
        name: 'price-compare',
        component: () => import('@/views/PriceCompare.vue'),
        meta: { title: '가격비교' },
      },
      {
        path: 'price-compare/:id',
        name: 'price-compare-detail',
        component: () => import('@/views/PriceCompare.vue'),
        meta: { title: '가격비교' },
      },
      {
        path: 'load-calc',
        name: 'load-calc',
        component: () => import('@/views/LoadCalc.vue'),
        meta: { title: '하중계산' },
      },
      {
        path: 'monitor',
        name: 'monitor',
        component: () => import('@/views/Monitor.vue'),
        meta: { title: 'KPI 모니터링' },
      },
      {
        path: 'tire-import',
        name: 'tire-import',
        component: () => import('@/views/TireImport.vue'),
        meta: { title: '인도네시아 타이어 수입량' },
      },
      {
        path: 'margin',
        name: 'margin',
        component: () => import('@/views/Margin.vue'),
        meta: { title: '마진 분석' },
      },
      {
        path: 'branch-sales',
        name: 'branch-sales',
        component: () => import('@/views/BranchSales.vue'),
        meta: { title: '지점 판매 현황' },
      },
      {
        path: 'labor-cost',
        name: 'labor-cost',
        component: () => import('@/views/LaborCost.vue'),
        meta: { title: '인건비' },
      },
      {
        path: 'docs',
        name: 'docs',
        component: () => import('@/views/Docs.vue'),
        meta: { title: '정리', scope: 'company' },
      },
      {
        // 개인 자료실 — '정리'와 같은 게시판(Docs.vue)을 scope 로만 분리해 재사용
        path: 'seo-docs',
        name: 'seo-docs',
        component: () => import('@/views/Docs.vue'),
        meta: { title: 'SEO자료', scope: 'personal' },
      },
      {
        path: 'databases',
        name: 'databases',
        component: () => import('@/views/Databases.vue'),
        meta: { title: '회사 DB' },
      },
    ],
  },
  {
    path: '/login',
    name: 'login',
    component: () => import('@/views/PinLogin.vue'),
    meta: { public: true },
  },
  {
    path: '/:pathMatch(.*)*',
    name: 'not-found',
    component: () => import('@/views/NotFound.vue'),
    meta: { public: true },
  },
];

const router = createRouter({
  history: createWebHashHistory(),
  routes,
});

router.beforeEach(async (to) => {
  const { data } = await supabase.auth.getSession();
  const hasSession = !!data.session;

  // 비로그인 → 보호 경로 접근 차단
  if (!hasSession) {
    sessionStorage.removeItem('asura_auth');
    if (!to.meta.public) return '/login';
    return;
  }

  // 세션은 있으나 역할 캐시가 없으면(탭 재오픈 등) 복원
  let role = sessionStorage.getItem('asura_auth');
  if (!role) role = await syncRoleFromSession();

  // 역할 기반 페이지 게이팅 — 4역할 모델
  //   super_admin / staff : 모든 경로 허용
  //   distributor / end_user : /quote + /price-compare(고객용) 만 허용 (원가·내부정보 차단)
  //   알 수 없는/누락 역할도 보수적으로 제한
  const isPrivileged = role === 'super_admin' || role === 'staff';
  const customerAllowed = to.path === '/quote' || to.path.startsWith('/price-compare');
  if (!isPrivileged && !to.meta.public && !customerAllowed) return '/quote';
});

// 최근 방문 페이지 기록 (Command Palette용)
router.afterEach((to) => {
  const title = to.meta.title as string | undefined;
  if (title && !to.meta.public) pushRecent(to.path, title);
});

export default router;
