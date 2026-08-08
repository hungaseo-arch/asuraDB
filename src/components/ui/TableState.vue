<script setup lang="ts">
// 표 본문(tbody) 안의 3가지 비정상 상태를 한 곳에서 처리한다 — 로딩 스켈레톤 / 에러+재시도 / 빈 상태.
// 사용법: 데이터 행(v-for)의 바로 앞에 두고 v-if / v-else 로 짝을 맞춘다.
//
//   <tbody>
//     <TableState v-if="loading || error || !rows.length"
//                 :colspan="COLS" :loading="loading" :error="error"
//                 empty-text="조건에 맞는 자료가 없습니다." @retry="load" />
//     <tr v-for="r in rows" v-else :key="r.id"> … </tr>
//   </tbody>
import { RotateCw, TriangleAlert } from 'lucide-vue-next';

const props = withDefaults(defineProps<{
  colspan: number;
  loading?: boolean;
  error?: string | null;
  loadingText?: string;
  emptyText?: string;
  skeletonRows?: number;
}>(), {
  loading: false,
  error: null,
  loadingText: '불러오는 중…',
  emptyText: '표시할 자료가 없습니다.',
  skeletonRows: 5,
});

defineEmits<{ retry: [] }>();

// 스켈레톤 막대 폭을 행마다 조금씩 달리해 '실제 표가 채워지는 중' 처럼 보이게 한다.
const WIDTHS = ['92%', '78%', '85%', '70%', '88%', '74%'];
const barWidth = (n: number) => WIDTHS[(n - 1) % WIDTHS.length];
</script>

<template>
  <!-- 로딩: 스켈레톤 행 (스크린리더에는 상태 텍스트만 전달) -->
  <template v-if="props.loading">
    <tr v-for="n in props.skeletonRows" :key="n" class="border-b border-border/50 last:border-b-0" aria-hidden="true">
      <td :colspan="props.colspan" class="px-3 py-3">
        <div class="h-3.5 rounded bg-muted animate-pulse" :style="{ width: barWidth(n) }" />
      </td>
    </tr>
    <tr>
      <td :colspan="props.colspan" class="sr-only">
        <span role="status" aria-live="polite">{{ props.loadingText }}</span>
      </td>
    </tr>
  </template>

  <!-- 에러: 사유 + 재시도 (기존에는 조용히 빈 화면이었다) -->
  <tr v-else-if="props.error">
    <td :colspan="props.colspan" class="px-3 py-10">
      <div role="alert" class="flex flex-col items-center gap-2 text-center">
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
    </td>
  </tr>

  <!-- 빈 상태 -->
  <tr v-else>
    <td :colspan="props.colspan" class="px-3 py-10 text-center text-sm text-muted-foreground">
      {{ props.emptyText }}
    </td>
  </tr>
</template>
