<script setup lang="ts">
defineProps<{ size?: number | string }>();
</script>

<template>
  <svg :width="size ?? 14" :height="size ?? 14" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
    <rect width="24" height="24" rx="5" fill="#1DB446"/>
    <path d="M6 5h6.5a4 4 0 0 1 2.914 6.754A4 4 0 0 1 12.5 19H6V5zm3 3v3h3.5a1.5 1.5 0 0 0 0-3H9zm0 6v3h3.5a1.5 1.5 0 0 0 0-3H9z" fill="white"/>
  </svg>
</template>
