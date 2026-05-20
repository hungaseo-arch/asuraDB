<script setup lang="ts">
import { TooltipRoot } from 'reka-ui';

// shadcn-vue Tooltip root — thin wrapper exposing reka-ui props.
defineProps<{ delayDuration?: number; disableHoverableContent?: boolean }>();
</script>

<template>
  <TooltipRoot
    :delay-duration="delayDuration ?? 0"
    :disable-hoverable-content="disableHoverableContent"
  >
    <slot />
  </TooltipRoot>
</template>
