<script setup lang="ts">
import { computed, ref } from 'vue';
import { cn } from '@/lib/utils';

// shadcn-vue Input — supports v-model. Original shadcn/ui Input.tsx equivalent.
const props = defineProps<{
  modelValue?: string | number;
  type?: string;
  placeholder?: string;
  disabled?: boolean;
  class?: string;
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: string): void;
  (e: 'keydown', event: KeyboardEvent): void;
}>();

const classes = computed(() =>
  cn(
    'flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm transition-colors',
    'file:border-0 file:bg-transparent file:text-sm file:font-medium',
    'placeholder:text-muted-foreground',
    'focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring',
    'disabled:cursor-not-allowed disabled:opacity-50',
    props.class,
  ),
);

function onInput(e: Event) {
  emit('update:modelValue', (e.target as HTMLInputElement).value);
}

// 커스텀 컴포넌트라 부모의 template ref 는 컴포넌트 인스턴스를 가리킨다.
// 네이티브 input 처럼 focus() 를 쓸 수 있도록 명시적으로 노출한다.
// (미노출 시 inputRef.value.focus 가 undefined → Search.vue mounted 훅에서 예외)
const inputEl = ref<HTMLInputElement | null>(null);
function focus() { inputEl.value?.focus(); }
defineExpose({ focus });
</script>

<template>
  <input
    ref="inputEl"
    :type="type ?? 'text'"
    :value="modelValue"
    :placeholder="placeholder"
    :disabled="disabled"
    :class="classes"
    @input="onInput"
    @keydown="$emit('keydown', $event)"
  />
</template>
