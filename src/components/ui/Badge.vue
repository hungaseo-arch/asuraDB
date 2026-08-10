<script setup lang="ts">
import { computed } from 'vue';
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '@/lib/utils';

// shadcn-vue Badge — shadcn/ui Badge.tsx 기반, 배색은 60-30-10 가이드를 따른다.
// 가이드 3항대로 배지 바탕은 파스텔, 글자는 진한 톤을 쓴다.
// 상태 배지(success/warning/info/danger)는 배경 + 같은 계열 진한 글자 + 계열
// 테두리 3종 세트로, 색맹 사용자도 테두리로 구분할 수 있게 한다.
const badgeVariants = cva(
  'inline-flex items-center rounded-md border px-2 py-0.5 text-xs font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2',
  {
    variants: {
      variant: {
        default: 'bg-primary-soft text-primary-soft-foreground border-border hover:bg-secondary',
        solid: 'border-transparent bg-primary text-primary-foreground hover:bg-primary/80',
        secondary: 'border-transparent bg-secondary text-secondary-foreground hover:bg-secondary/80',
        destructive: 'border-transparent bg-destructive text-destructive-foreground hover:bg-destructive/80',
        outline: 'text-foreground',
        success: 'bg-success-soft text-success border-success-border',
        warning: 'bg-warning-soft text-warning border-warning-border',
        danger: 'bg-destructive-soft text-destructive border-destructive-border',
        info: 'bg-info-soft text-info border-info-border',
      },
    },
    defaultVariants: { variant: 'default' },
  },
);

type BadgeVariant = NonNullable<VariantProps<typeof badgeVariants>['variant']>;

const props = defineProps<{
  variant?: BadgeVariant;
  class?: string;
}>();

const classes = computed(() =>
  cn(badgeVariants({ variant: props.variant ?? 'default' }), props.class),
);
</script>

<template>
  <span :class="classes">
    <slot />
  </span>
</template>
