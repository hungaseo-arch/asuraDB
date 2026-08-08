<script setup lang="ts">
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import AsuraLogo from '@/components/icons/AsuraLogo.vue';
import { Loader2 } from 'lucide-vue-next';
import { signIn, type Role } from '@/lib/auth';
import { LAUNCHER_BASE, IS_HOST } from '@/lib/api';

const router = useRouter();

// 로그인 성공 즉시 검색/AI 백엔드(8000)를 런처(8001) 경유로 예열한다.
// 첫 기동은 임베딩 모델 로딩으로 ~20s 걸리므로, 앱 진입 전에 미리 시작해 대기를 줄인다.
// 런처(LaunchAgent, 상시)가 죽어 있어도 조용히 무시 — Layout onMounted 가 한 번 더 시도한다.
// 호스트 PC 가 아니면(배포본) 예열 대상이 없으므로 요청을 만들지 않는다 — mixed content 방지.
function warmUpApi() {
  if (!IS_HOST) return;
  fetch(`${LAUNCHER_BASE}/start`, { method: 'POST', keepalive: true }).catch(() => {});
}

const email    = ref('');
const password = ref('');
const checking = ref(false);
const errorMsg = ref('');

// 로그인 후 역할별 진입 페이지
function landingFor(role: Role | null): string {
  if (role === 'super_admin' || role === 'staff') return '/';
  return '/quote';   // distributor · end_user · 알 수 없음 → 견적서 페이지
}

async function submit() {
  if (!email.value.trim() || !password.value) return;
  checking.value = true;
  errorMsg.value = '';
  try {
    const role = await signIn(email.value.trim(), password.value);
    warmUpApi();   // 로그인 성공 → API 예열(비차단)
    router.replace(landingFor(role));
  } catch (e) {
    errorMsg.value = e instanceof Error ? e.message : String(e);
    password.value = '';
  } finally {
    checking.value = false;
  }
}
</script>

<template>
  <div class="min-h-screen bg-background flex items-center justify-center p-4">
    <form
      class="flex flex-col items-center gap-7 w-80"
      @submit.prevent="submit"
    >
      <!-- Logo -->
      <div class="flex flex-col items-center gap-3">
        <AsuraLogo :size="56" style="filter: drop-shadow(0 0 16px rgba(38,126,255,0.5));" />
        <div class="text-center">
          <div class="font-bold text-lg tracking-tight">AsuraDB</div>
          <div class="text-xs text-muted-foreground mt-0.5">이메일로 로그인</div>
        </div>
      </div>

      <!-- Inputs -->
      <div class="w-full flex flex-col gap-2">
        <label class="text-xs text-muted-foreground" for="login-email">이메일</label>
        <input
          id="login-email"
          v-model="email"
          type="email"
          autocomplete="email"
          required
          :disabled="checking"
          class="h-10 rounded-lg border border-input bg-card px-3 text-sm focus:outline-none focus:ring-2 focus:ring-primary/40 disabled:opacity-60"
          placeholder="you@example.com"
        />

        <label class="text-xs text-muted-foreground mt-2" for="login-password">비밀번호</label>
        <input
          id="login-password"
          v-model="password"
          type="password"
          autocomplete="current-password"
          required
          :disabled="checking"
          class="h-10 rounded-lg border border-input bg-card px-3 text-sm focus:outline-none focus:ring-2 focus:ring-primary/40 disabled:opacity-60"
          placeholder="••••••••"
        />
      </div>

      <!-- Error -->
      <p
        v-if="errorMsg"
        class="text-xs text-red-600 text-center -mt-2 max-w-full wrap-break-word"
      >{{ errorMsg }}</p>

      <!-- Submit -->
      <button
        type="submit"
        :disabled="checking || !email || !password"
        class="w-full h-10 rounded-lg bg-primary text-primary-foreground font-semibold text-sm hover:bg-primary/90 active:scale-[0.98] transition-all duration-100 disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
      >
        <Loader2 v-if="checking" :size="14" class="animate-spin" />
        {{ checking ? '확인 중…' : '로그인' }}
      </button>
    </form>
  </div>
</template>
