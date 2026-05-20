<script setup lang="ts">
import { computed } from 'vue';
import { TooltipContent as RekaContent, TooltipPortal } from 'reka-ui';
import { cn } from '@/lib/utils';

const props = defineProps<{
  side?: 'top' | 'right' | 'bottom' | 'left';
  sideOffset?: number;
  class?: string;
}>();

const classes = computed(() =>
  cn(
    'z-50 overflow-hidden rounded-md border bg-popover px-3 py-1.5 text-xs text-popover-foreground shadow-md',
    'animate-in fade-in-0 zoom-in-95 data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:zoom-out-95',
    'data-[side=bottom]:slide-in-from-top-2 data-[side=left]:slide-in-from-right-2',
    'data-[side=right]:slide-in-from-left-2 data-[side=top]:slide-in-from-bottom-2',
    props.class,
  ),
);
</script>

<template>
  <TooltipPortal>
    <RekaContent :side="side ?? 'top'" :side-offset="sideOffset ?? 4" :class="classes">
      <slot />
    </RekaContent>
  </TooltipPortal>
</template>
