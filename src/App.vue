<script setup lang="ts">
import { TooltipProvider } from 'reka-ui';
import { Toaster } from 'vue-sonner';
import { RouterView } from 'vue-router';
</script>

<template>
  <TooltipProvider :delay-duration="0">
    <RouterView />
    <Toaster position="bottom-right" :rich-colors="true" />
  </TooltipProvider>
</template>
