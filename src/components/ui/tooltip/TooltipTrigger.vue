<script setup lang="ts">
import { TooltipTrigger as RekaTrigger } from 'reka-ui';

// `as-child` mirrors Radix React `asChild` — passes attrs onto the slot.
defineProps<{ asChild?: boolean }>();
</script>

<template>
  <RekaTrigger :as-child="asChild ?? true">
    <slot />
  </RekaTrigger>
</template>
