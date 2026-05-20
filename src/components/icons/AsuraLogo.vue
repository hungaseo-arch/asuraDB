<script setup lang="ts">
defineProps<{ size?: number; mono?: boolean }>();
</script>

<template>
  <svg
    :width="size ?? 32"
    :height="size ?? 32"
    viewBox="0 0 64 64"
    xmlns="http://www.w3.org/2000/svg"
    aria-label="AsuraDB"
  >
    <path
      :fill="mono ? '#FFFFFF' : '#267EFF'"
      fill-rule="evenodd"
      d="M32 1 C51 1,63 13,63 32 C63 51,51 63,32 63 C13 63,1 51,1 32 C1 13,13 1,32 1 Z
         M38.25 9 L17.5 35.5 L28 35.5 L24.75 55 L46.5 28 L35.5 28 L38.25 9 Z"
    />
  </svg>
</template>
