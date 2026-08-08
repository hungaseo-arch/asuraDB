<script setup lang="ts">
import { onMounted } from 'vue';
import { useRoute } from 'vue-router';
import AsuraLogo from '@/components/icons/AsuraLogo.vue';
import { Home, BarChart3, Package, ClipboardList } from 'lucide-vue-next';

const route = useRoute();

// 404 는 로그인 여부와 무관한 public 라우트라 앱 셸(Layout) 밖에서 렌더된다.
// 그래서 헤더·네비 대신 로고 + 주요 메뉴 바로가기를 이 화면 안에 직접 둔다.
const SHORTCUTS = [
  { to: '#/home',     icon: Home,          label: '홈' },
  { to: '#/monitor',  icon: BarChart3,     label: 'KPI 모니터링' },
  { to: '#/databases', icon: Package,      label: '회사 DB' },
  { to: '#/quote',    icon: ClipboardList, label: '견적서 작성' },
];

onMounted(() => {
  // 잘못된 링크 추적용 기록 — 앱 결함이 아니라 사용자 이동이므로 error 가 아닌 warn 으로 남긴다
  // (E2E 스모크의 '콘솔 에러 0건' 기준을 흐리지 않기 위해서도 warn 이 맞다)
  // eslint-disable-next-line no-console
  console.warn('404: 존재하지 않는 경로 접근 —', route.fullPath);
});
</script>

<template>
  <div class="min-h-screen flex flex-col bg-background">
    <!-- 앱 헤더와 같은 위치·높이의 간이 헤더 (Layout 밖이라 네비게이션은 없음) -->
    <header class="h-14 shrink-0 border-b border-border bg-card flex items-center gap-2 px-4">
      <a href="#/home" class="flex items-center gap-2" title="홈">
        <AsuraLogo :size="26" class="shrink-0" />
        <span class="font-bold text-lg text-foreground">AsuraDB</span>
      </a>
    </header>

    <main class="flex-1 flex items-center justify-center p-6">
      <div class="w-full max-w-md text-center space-y-5">
        <p class="text-5xl font-extrabold tabular-nums text-primary/80">404</p>
        <div class="space-y-1.5">
          <h1 class="text-lg font-bold text-foreground">페이지를 찾을 수 없습니다</h1>
          <p class="text-sm text-muted-foreground">
            주소가 바뀌었거나 삭제된 페이지입니다.
          </p>
          <p class="text-xs text-muted-foreground/70 font-mono break-all">{{ route.fullPath }}</p>
        </div>

        <nav class="grid grid-cols-2 gap-2 pt-1" aria-label="주요 메뉴 바로가기">
          <a
            v-for="s in SHORTCUTS" :key="s.to" :href="s.to"
            class="inline-flex items-center gap-2 rounded-lg border border-border bg-card px-3 py-2.5 text-sm text-foreground/80 hover:bg-accent hover:text-accent-foreground transition-colors"
          >
            <component :is="s.icon" :size="15" class="shrink-0" />
            <span class="truncate">{{ s.label }}</span>
          </a>
        </nav>

        <a href="#/home" class="inline-block text-sm text-primary hover:text-primary/80 underline">
          홈으로 돌아가기
        </a>
      </div>
    </main>
  </div>
</template>
