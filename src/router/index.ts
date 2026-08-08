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
        meta: { title: '홈', desc: '사내 대시보드 홈 — 주요 지표·자료·최근 방문 요약' },
      },
      {
        path: 'search',
        name: 'search',
        component: () => import('@/views/Search.vue'),
        meta: { title: '로컬 검색', desc: '사내 문서·자료 로컬 전문 검색 (호스트 PC 전용)' },
      },
      {
        path: 'ai-search',
        name: 'ai-search',
        component: () => import('@/views/AiSearch.vue'),
        meta: { title: 'AI 지식 Q&A', desc: '사내 자료 기반 AI 질의응답 (호스트 PC 전용)' },
      },
      {
        path: 'quote',
        name: 'quote',
        component: () => import('@/views/Quote.vue'),
        meta: { title: '견적서 작성', desc: '타이어 견적서 작성·인쇄' },
      },
      {
        path: 'price-compare',
        name: 'price-compare',
        component: () => import('@/views/PriceCompare.vue'),
        meta: { title: '가격비교', desc: '경쟁사·거래처 타이어 가격 비교' },
      },
      {
        path: 'price-compare/:id',
        name: 'price-compare-detail',
        component: () => import('@/views/PriceCompare.vue'),
        meta: { title: '가격비교', desc: '경쟁사·거래처 타이어 가격 비교' },
      },
      {
        path: 'load-calc',
        name: 'load-calc',
        component: () => import('@/views/LoadCalc.vue'),
        meta: { title: '하중계산', desc: '축하중 기준 타이어 하중·공기압 계산' },
      },
      {
        path: 'monitor',
        name: 'monitor',
        component: () => import('@/views/Monitor.vue'),
        meta: { title: 'KPI 모니터링', desc: '시장·경쟁·재무 KPI 월별 모니터링' },
      },
      {
        path: 'tire-import',
        name: 'tire-import',
        component: () => import('@/views/TireImport.vue'),
        meta: { title: '인도네시아 타이어 수입량', desc: 'HS 코드별 인도네시아 타이어 수입 통계 (BPS EXIM)' },
      },
      {
        path: 'margin',
        name: 'margin',
        component: () => import('@/views/Margin.vue'),
        meta: { title: '마진 분석', desc: '브랜드·제품·고객별 매출·마진 분석' },
      },
      {
        path: 'branch-sales',
        name: 'branch-sales',
        component: () => import('@/views/BranchSales.vue'),
        meta: { title: '지점 판매 현황', desc: '지점별 판매 실적과 손익(P&L) 현황' },
      },
      {
        path: 'labor-cost',
        name: 'labor-cost',
        component: () => import('@/views/LaborCost.vue'),
        meta: { title: '인건비', desc: '월별 인건비·인원 현황과 급여 상세' },
      },
      {
        path: 'docs',
        name: 'docs',
        component: () => import('@/views/Docs.vue'),
        meta: { title: 'ASCENDO자료', scope: 'company', desc: '회사 자료·검토 문서 게시판' },
      },
      {
        // 개인 자료실 — '정리'와 같은 게시판(Docs.vue)을 scope 로만 분리해 재사용
        path: 'seo-docs',
        name: 'seo-docs',
        component: () => import('@/views/Docs.vue'),
        meta: { title: 'SEO자료', scope: 'personal', desc: '개인 자료·참고 문서 게시판' },
      },
      {
        path: 'databases',
        name: 'databases',
        component: () => import('@/views/Databases.vue'),
        meta: { title: '회사 DB', desc: '제품·가격·제원·거래처 사내 데이터베이스' },
      },
      {
        path: 'tools/dot-lookup',
        name: 'dot-lookup',
        component: () => import('@/views/tools/DotLookup.vue'),
        meta: { title: 'DOT 공장코드 조회', desc: 'DOT 코드로 타이어 생산 공장·생산주차 조회' },
      },
    ],
  },
  {
    path: '/login',
    name: 'login',
    component: () => import('@/views/PinLogin.vue'),
    meta: { public: true, desc: 'AsuraDB 로그인' },
  },
  {
    path: '/:pathMatch(.*)*',
    name: 'not-found',
    component: () => import('@/views/NotFound.vue'),
    meta: { public: true, desc: '요청한 페이지를 찾을 수 없습니다' },
  },
];

const router = createRouter({
  history: createWebHashHistory(),
  routes,
  // 앱 셸이 스크롤 컨테이너(<main>)를 따로 두고 있어 window 스크롤은 거의 쓰이지 않지만,
  // 인쇄 해제 등으로 window 가 스크롤된 경우까지 확실히 맨 위로 되돌린다.
  // (<main> 초기화는 Layout.vue 의 라우트 watch 가 담당)
  scrollBehavior: () => ({ top: 0 }),
});

// 브라우저 탭·히스토리 구분용 문서 제목 — 라우트 meta.title 기준
const APP_NAME = 'AsuraDB';
// index.html 의 기본 설명 (라우트에 meta.desc 가 없을 때로 되돌릴 값)
const DEFAULT_DESC = 'AsuraDB · 사내 업무용 대시보드';   // index.html 의 <meta name="description"> 과 동일

// 문서 제목과 같은 방식으로 meta[name=description] 도 라우트마다 갱신한다.
// 사이트는 noindex 라 검색 노출용은 아니고, 링크 미리보기·북마크·브라우저 히스토리에서 페이지를 구분하는 용도.
function setMetaDescription(desc: string) {
  let tag = document.querySelector<HTMLMetaElement>('meta[name="description"]');
  if (!tag) {
    tag = document.createElement('meta');
    tag.name = 'description';
    document.head.appendChild(tag);
  }
  tag.content = desc;
}


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

// 최근 방문 페이지 기록 (Command Palette용) + 문서 제목 갱신
router.afterEach((to) => {
  const title = to.meta.title as string | undefined;
  if (title && !to.meta.public) pushRecent(to.path, title);
  // 견적·가격비교는 인쇄 시 파일명을 위해 document.title 을 잠시 바꿨다 되돌리므로 여기서만 설정한다
  document.title = title ? `${title} — ${APP_NAME}` : APP_NAME;
  setMetaDescription((to.meta.desc as string | undefined) ?? DEFAULT_DESC);
});

export default router;
