<script setup lang="ts">
import { computed } from 'vue';
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '@/lib/utils';

// shadcn-vue Button — shadcn/ui Button.tsx 기반, 배색은 60-30-10 가이드를 따른다.
//
// default 와 solid 의 구분이 이 컴포넌트의 핵심이다(가이드 2항: 강조는 시선이
// 마지막에 머무는 한 곳). 화면 대부분의 버튼은 연한 배경 default 를 쓰고,
// 진한 solid 는 그 화면의 대표 실행 버튼 1개에만 쓴다.
const buttonVariants = cva(
  'inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:pointer-events-none disabled:opacity-50 [&_svg]:pointer-events-none [&_svg]:size-4 [&_svg]:shrink-0',
  {
    variants: {
      variant: {
        // 연한 배경(#E3F2FD) + 진한 텍스트(#37474F) — 대비 8.45:1
        // hover 는 secondary(#ECEFF1). accent 는 primary-soft 와 같은 값이라
        // hover:bg-accent 로는 변화가 보이지 않는다.
        default: 'bg-primary-soft text-primary-soft-foreground border border-border shadow-sm hover:bg-secondary',
        // 주요 CTA 전용 — 화면당 1개
        solid: 'bg-primary text-primary-foreground shadow hover:bg-primary/90',
        destructive: 'bg-destructive text-destructive-foreground shadow-sm hover:bg-destructive/90',
        outline: 'border border-input bg-card shadow-sm hover:bg-accent hover:text-accent-foreground',
        secondary: 'bg-secondary text-secondary-foreground shadow-sm hover:bg-secondary/80',
        ghost: 'hover:bg-accent hover:text-accent-foreground',
        link: 'text-primary underline-offset-4 hover:underline',
      },
      size: {
        default: 'h-9 px-4 py-2',
        sm: 'h-8 rounded-md px-3 text-xs',
        lg: 'h-10 rounded-md px-8',
        icon: 'h-9 w-9',
      },
    },
    defaultVariants: { variant: 'default', size: 'default' },
  },
);

type ButtonVariant = NonNullable<VariantProps<typeof buttonVariants>['variant']>;
type ButtonSize = NonNullable<VariantProps<typeof buttonVariants>['size']>;

const props = defineProps<{
  variant?: ButtonVariant;
  size?: ButtonSize;
  type?: 'button' | 'submit' | 'reset';
  disabled?: boolean;
  class?: string;
}>();

defineEmits<{ (e: 'click', event: MouseEvent): void }>();

const classes = computed(() =>
  cn(buttonVariants({ variant: props.variant ?? 'default', size: props.size ?? 'default' }), props.class),
);
</script>

<template>
  <button
    :type="type ?? 'button'"
    :disabled="disabled"
    :class="classes"
    @click="$emit('click', $event)"
  >
    <slot />
  </button>
</template>
