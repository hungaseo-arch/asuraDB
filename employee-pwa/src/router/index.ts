import { createRouter, createWebHashHistory } from 'vue-router';

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
    },
    {
      path: '/history',
      name: 'history',
      component: () => import('@/views/History.vue'),
    },
  ],
});

export default router;
