import { createRouter, createWebHashHistory } from 'vue-router';
import { supabase } from '@/lib/supabase';

const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    {
      path: '/',
      name: 'checkin',
      component: () => import('@/views/CheckIn.vue'),
    },
    {
      path: '/leave',
      name: 'leave',
      component: () => import('@/views/LeaveRequest.vue'),
      meta: { requiresAuth: true },
    },
    {
      path: '/history',
      name: 'history',
      component: () => import('@/views/History.vue'),
      meta: { requiresAuth: true },
    },
  ],
});

// 세션 가드 — 로그인 화면은 '/'(CheckIn)에 있으므로 미로그인 상태로 하위 화면에 진입하면 되돌린다.
router.beforeEach(async (to) => {
  if (!to.meta.requiresAuth) return true;
  const { data: { session } } = await supabase.auth.getSession();
  return session ? true : { path: '/' };
});

export default router;
