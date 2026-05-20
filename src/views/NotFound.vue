<script setup lang="ts">
import { onMounted } from 'vue';
import { useRoute } from 'vue-router';

const route = useRoute();

onMounted(() => {
  // eslint-disable-next-line no-console
  console.error('404 Error: User attempted to access non-existent route:', route.fullPath);
});
</script>

<template>
  <div class="min-h-screen flex items-center justify-center bg-background">
    <div class="text-center">
      <h1 class="text-4xl font-bold mb-4 text-foreground">404</h1>
      <p class="text-xl text-muted-foreground mb-4">Oops! Page not found</p>
      <a href="#/" class="text-primary hover:text-primary/80 underline">
        Return to Home
      </a>
    </div>
  </div>
</template>
