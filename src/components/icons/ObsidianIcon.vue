<script setup lang="ts">
defineProps<{ size?: number | string }>();
</script>

<!-- Obsidian brand icon — purple crystal gem shape -->
<template>
  <svg :width="size ?? 14" :height="size ?? 14" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
    <!-- Top facet (lightest) -->
    <path d="M12 2 L19.5 7.5 L12 11 L4.5 7.5 Z" fill="#a855f7"/>
    <!-- Left facet -->
    <path d="M4.5 7.5 L12 11 L9 22 Z" fill="#7c3aed"/>
    <!-- Right facet -->
    <path d="M19.5 7.5 L12 11 L15 22 Z" fill="#9333ea"/>
    <!-- Bottom facet -->
    <path d="M9 22 L12 11 L15 22 Z" fill="#6d28d9"/>
  </svg>
</template>
