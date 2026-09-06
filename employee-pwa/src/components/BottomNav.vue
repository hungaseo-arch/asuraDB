<script setup lang="ts">
import { useRouter } from 'vue-router';

defineProps<{ active: 'checkin' | 'leave' | 'history' }>();
const router = useRouter();

const items = [
  { key: 'checkin', path: '/', icon: '🕐', label: '출퇴근' },
  { key: 'leave', path: '/leave', icon: '📝', label: '휴가' },
  { key: 'history', path: '/history', icon: '📋', label: '기록' },
] as const;
</script>

<template>
  <nav class="fixed bottom-0 left-0 right-0 bg-card border-t border-border flex">
    <button v-for="item in items" :key="item.key" @click="router.push(item.path)"
      :class="['flex-1 py-3 flex flex-col items-center gap-0.5',
               active === item.key ? 'text-primary font-semibold' : 'text-muted-foreground']">
      <span class="text-lg">{{ item.icon }}</span>
      <span class="text-xs font-medium">{{ item.label }}</span>
    </button>
  </nav>
</template>
