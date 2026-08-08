<script setup lang="ts">
// 표가 아닌 영역(카드·차트·목록)의 로딩/에러/빈 상태 표준 표시.
// 표 안에서는 TableState.vue 를 쓴다.
//
//   <DataState :loading="loading" :error="error" :empty="!rows.length"
//              empty-text="선택한 월에 자료가 없습니다." @retry="load">
//     …정상 콘텐츠…
//   </DataState>
import { RotateCw, TriangleAlert } from 'lucide-vue-next';

const props = withDefaults(defineProps<{
  loading?: boolean;
  error?: string | null;
  empty?: boolean;
  loadingText?: string;
  emptyText?: string;
  /** 로딩 스켈레톤 높이 (Tailwind 클래스) */
  skeletonClass?: string;
}>(), {
  loading: false,
  error: null,
  empty: false,
  loadingText: '불러오는 중…',
  emptyText: '표시할 자료가 없습니다.',
  skeletonClass: 'h-24',
});

defineEmits<{ retry: [] }>();
</script>

<template>
  <div v-if="props.loading" :class="['rounded-xl bg-muted animate-pulse', props.skeletonClass]">
    <span class="sr-only" role="status" aria-live="polite">{{ props.loadingText }}</span>
  </div>

  <div
    v-else-if="props.error"
    role="alert"
    class="flex flex-col items-center gap-2 rounded-xl border border-border bg-card px-4 py-8 text-center"
  >
    <TriangleAlert :size="20" class="text-destructive" />
    <p class="text-sm font-semibold text-foreground">자료를 불러오지 못했습니다</p>
    <p class="text-xs text-muted-foreground break-all max-w-md">{{ props.error }}</p>
    <button
      type="button"
      class="mt-1 inline-flex items-center gap-1.5 rounded-lg border border-border bg-card px-3 py-1.5 text-xs font-medium text-foreground hover:bg-accent transition-colors"
      @click="$emit('retry')"
    >
      <RotateCw :size="13" /> 다시 시도
    </button>
  </div>

  <p v-else-if="props.empty" class="rounded-xl border border-border bg-card px-4 py-8 text-center text-sm text-muted-foreground">
    {{ props.emptyText }}
  </p>

  <slot v-else />
</template>
