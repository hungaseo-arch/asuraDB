<script setup lang="ts">
import { computed } from 'vue';
import { cn } from '@/lib/utils';

// shadcn-vue Card (root).
const props = defineProps<{ class?: string }>();
const classes = computed(() =>
  cn('rounded-xl border bg-card text-card-foreground shadow', props.class),
);
</script>

<template>
  <div :class="classes">
    <slot />
  </div>
</template>
