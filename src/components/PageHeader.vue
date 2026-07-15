<script setup lang="ts">
// 전 페이지 공통 헤더 — 제목은 상단 네비게이션에 표시되므로 본문에선 부제만.
// 가로 3분할: ① 정보(부제) ② 선택(탭·필터·드롭박스) ③ 기타(버튼 등)
// title prop은 상단 표시(라우터 meta.title)와의 호환/문서용으로 유지.
defineProps<{ title?: string; subtitle?: string }>();
</script>

<template>
  <div class="flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
    <!-- ① 상세 페이지 정보 (부제) -->
    <div class="min-w-0">
      <p v-if="subtitle" class="text-xs text-muted-foreground">{{ subtitle }}</p>
      <slot name="subtitle" />
    </div>

    <!-- ② 선택 관련 (탭·필터·드롭박스) -->
    <div v-if="$slots.controls" class="flex flex-wrap items-center gap-2 min-w-0">
      <slot name="controls" />
    </div>

    <!-- ③ 기타 정보 (버튼 등) -->
    <div v-if="$slots.actions" class="flex flex-wrap items-center gap-2">
      <slot name="actions" />
    </div>
  </div>
</template>
