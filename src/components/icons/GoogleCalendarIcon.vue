<script setup lang="ts">
defineProps<{ size?: number | string }>();
</script>

<!-- Google Calendar official logo -->
<template>
  <svg :width="size ?? 14" :height="size ?? 14" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
    <!-- White background square -->
    <rect x="2" y="2" width="20" height="20" rx="2" fill="white"/>
    <!-- Top blue bar -->
    <rect x="2" y="2" width="20" height="5" rx="2" fill="#4285F4"/>
    <rect x="2" y="5" width="20" height="2" fill="#4285F4"/>
    <!-- Left red strip -->
    <rect x="2" y="2" width="3" height="20" rx="1" fill="#EA4335"/>
    <rect x="2" y="7" width="3" height="15" fill="#EA4335"/>
    <!-- Date number "31" in blue -->
    <text x="12" y="19" text-anchor="middle" font-family="Arial,sans-serif" font-size="8" font-weight="bold" fill="#4285F4">31</text>
    <!-- Grid lines -->
    <line x1="8" y1="10" x2="22" y2="10" stroke="#E0E0E0" stroke-width="0.5"/>
    <line x1="8" y1="14" x2="22" y2="14" stroke="#E0E0E0" stroke-width="0.5"/>
    <line x1="12" y1="7" x2="12" y2="22" stroke="#E0E0E0" stroke-width="0.5"/>
    <line x1="17" y1="7" x2="17" y2="22" stroke="#E0E0E0" stroke-width="0.5"/>
  </svg>
</template>
