import { createRouter, createWebHashHistory, type RouteRecordRaw } from 'vue-router';
import Layout from '@/components/Layout.vue';

const routes: RouteRecordRaw[] = [
  {
    path: '/',
    component: Layout,
    children: [
      {
        path: '',
        redirect: '/search',
      },
      {
        path: 'search',
        name: 'search',
        component: () => import('@/views/Search.vue'),
        meta: { title: '통합 자료 검색' },
      },
      {
        path: 'ai-search',
        name: 'ai-search',
        component: () => import('@/views/AiSearch.vue'),
        meta: { title: 'AI 지식 Q&A' },
      },
      {
        path: 'report',
        name: 'report',
        component: () => import('@/views/Report.vue'),
        meta: { title: '자동화 레포트' },
      },
      {
        path: 'quote',
        name: 'quote',
        component: () => import('@/views/Quote.vue'),
        meta: { title: '견적서 생성' },
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

router.beforeEach((to) => {
  const auth = sessionStorage.getItem('asura_auth');
  if (!auth && !to.meta.public) return '/login';
  if (auth === 'quote' && !to.meta.public && to.path !== '/quote') return '/quote';
});

export default router;
