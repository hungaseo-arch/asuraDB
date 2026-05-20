<script setup lang="ts">
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import AsuraLogo from '@/components/icons/AsuraLogo.vue';

const PINS: Record<string, string> = { '0574': 'full', '0000': 'quote' };
const router = useRouter();

const digits  = ref<string[]>([]);
const shake   = ref(false);

function press(d: string) {
  if (digits.value.length >= 4) return;
  digits.value.push(d);
  if (digits.value.length === 4) verify();
}

function del() {
  digits.value.pop();
}

function verify() {
  const pin  = digits.value.join('');
  const role = PINS[pin];
  if (role) {
    sessionStorage.setItem('asura_auth', role);
    router.replace(role === 'full' ? '/' : '/quote');
  } else {
    shake.value = true;
    setTimeout(() => {
      shake.value  = false;
      digits.value = [];
    }, 600);
  }
}
</script>

<template>
  <div class="min-h-screen bg-background flex items-center justify-center">
    <div class="flex flex-col items-center gap-8 w-64">
      <!-- Logo -->
      <div class="flex flex-col items-center gap-3">
        <AsuraLogo :size="56" style="filter: drop-shadow(0 0 16px rgba(38,126,255,0.5));" />
        <div class="text-center">
          <div class="font-bold text-lg tracking-tight">AsuraDB</div>
          <div class="text-xs text-muted-foreground mt-0.5">PIN을 입력하세요</div>
        </div>
      </div>

      <!-- Dot indicators -->
      <div
        class="flex gap-3"
        :class="shake && 'animate-[shake_0.5s_ease]'"
      >
        <div
          v-for="i in 4"
          :key="i"
          class="w-3 h-3 rounded-full border-2 transition-all duration-150"
          :class="digits.length >= i
            ? 'bg-primary border-primary'
            : 'bg-transparent border-border'"
        />
      </div>

      <!-- Keypad -->
      <div class="grid grid-cols-3 gap-3 w-full">
        <button
          v-for="d in ['1','2','3','4','5','6','7','8','9']"
          :key="d"
          class="h-14 rounded-xl text-lg font-semibold bg-card border border-border hover:bg-accent hover:border-primary/30 active:scale-95 transition-all duration-100"
          @click="press(d)"
        >
          {{ d }}
        </button>
        <div />
        <button
          class="h-14 rounded-xl text-lg font-semibold bg-card border border-border hover:bg-accent hover:border-primary/30 active:scale-95 transition-all duration-100"
          @click="press('0')"
        >
          0
        </button>
        <button
          class="h-14 rounded-xl text-sm text-muted-foreground bg-card border border-border hover:bg-accent hover:text-foreground active:scale-95 transition-all duration-100"
          @click="del"
        >
          ⌫
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
@keyframes shake {
  0%, 100% { transform: translateX(0); }
  20%       { transform: translateX(-8px); }
  40%       { transform: translateX(8px); }
  60%       { transform: translateX(-6px); }
  80%       { transform: translateX(6px); }
}
</style>
