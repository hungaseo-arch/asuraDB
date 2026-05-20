<script setup lang="ts">
import { computed } from 'vue';
import { Separator as RekaSeparator } from 'reka-ui';
import { cn } from '@/lib/utils';

// shadcn-vue Separator — wraps reka-ui Separator (Radix Vue successor).
const props = defineProps<{
  orientation?: 'horizontal' | 'vertical';
  decorative?: boolean;
  class?: string;
}>();

const classes = computed(() =>
  cn(
    'shrink-0 bg-border',
    (props.orientation ?? 'horizontal') === 'horizontal' ? 'h-px w-full' : 'h-full w-px',
    props.class,
  ),
);
</script>

<template>
  <RekaSeparator
    :orientation="orientation ?? 'horizontal'"
    :decorative="decorative ?? true"
    :class="classes"
  />
</template>
