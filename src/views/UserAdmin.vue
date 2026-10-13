<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import { UserPlus, KeyRound, Trash2, X } from 'lucide-vue-next';
import Button from '@/components/ui/Button.vue';
import Badge from '@/components/ui/Badge.vue';
import DataState from '@/components/ui/DataState.vue';
import PageHeader from '@/components/PageHeader.vue';
import { supabase } from '@/lib/supabase';
import type { Role } from '@/lib/auth';
import { listUsers, createUser, setUserPassword, deleteUser, type AdminUser } from '@/lib/adminUsers';
import { formatWibShort } from '@/lib/datetime';

const ROLE_OPTIONS: { value: Role; label: string }[] = [
  { value: 'super_admin', label: 'Admin' },
  { value: 'staff',       label: 'Staff' },
  { value: 'distributor', label: 'Distributor' },
  { value: 'end_user',    label: 'Customer' },
];

const loading = ref(true);
const error = ref<string | null>(null);
const users = ref<AdminUser[]>([]);
const myId = ref<string | null>(null);
const notice = ref<string | null>(null);
const busy = ref(false);

async function loadData() {
  loading.value = true;
  error.value = null;
  try {
    users.value = await listUsers();
  } catch (e: any) {
    error.value = e.message || '사용자 목록을 불러오지 못했습니다';
  } finally {
    loading.value = false;
  }
}

onMounted(async () => {
  myId.value = (await supabase.auth.getSession()).data.session?.user.id ?? null;
  await loadData();
});

const sorted = computed(() =>
  [...users.value].sort((a, b) => (a.email ?? '').localeCompare(b.email ?? '')),
);

function roleLabel(role: string | null) {
  return ROLE_OPTIONS.find(r => r.value === role)?.label ?? (role || '-');
}
function roleVariant(role: string | null) {
  return role === 'super_admin' ? 'info' : role === 'staff' ? 'success' : 'default';
}

// ── 모달 (등록 / 비밀번호 재설정) ─────────────────────────────────────────
type Mode = 'create' | 'password';
const mode = ref<Mode | null>(null);
const target = ref<AdminUser | null>(null);
const fEmail = ref('');
const fRole = ref<Role>('staff');
const fPassword = ref('');
const formError = ref<string | null>(null);

function openCreate() {
  mode.value = 'create';
  target.value = null;
  fEmail.value = '';
  fRole.value = 'staff';
  fPassword.value = '';
  formError.value = null;
}
function openPassword(u: AdminUser) {
  mode.value = 'password';
  target.value = u;
  fPassword.value = '';
  formError.value = null;
}
function closeModal() {
  mode.value = null;
}

async function submit() {
  if (fPassword.value && fPassword.value.length < 8) {
    formError.value = '비밀번호는 8자 이상이어야 합니다';
    return;
  }
  busy.value = true;
  formError.value = null;
  try {
    if (mode.value === 'create') {
      await createUser(fEmail.value.trim(), fRole.value, fPassword.value);
      notice.value = `${fEmail.value.trim()} 계정을 등록했습니다${fPassword.value ? '' : ' (기본 비밀번호)'}`;
    } else if (target.value) {
      await setUserPassword(target.value.id, fPassword.value);
      notice.value = `${target.value.email} 비밀번호를 ${fPassword.value ? '변경' : '기본 비밀번호로 초기화'}했습니다 (기존 로그인 세션 종료)`;
    }
    closeModal();
    await loadData();
  } catch (e: any) {
    formError.value = e.message;
  } finally {
    busy.value = false;
  }
}

async function remove(u: AdminUser) {
  if (!confirm(`${u.email} 계정을 삭제할까요?\n삭제하면 되돌릴 수 없습니다.`)) return;
  busy.value = true;
  try {
    await deleteUser(u.id);
    notice.value = `${u.email} 계정을 삭제했습니다`;
    await loadData();
  } catch (e: any) {
    error.value = e.message;
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div class="p-4 sm:p-6 space-y-6">
    <PageHeader title="사용자 관리" desc="로그인 계정 등록·삭제와 비밀번호 재설정 (관리자 전용)" />

    <div class="flex flex-wrap items-center gap-3">
      <p class="text-sm text-muted-foreground">비밀번호를 비워 두면 기본 비밀번호로 설정됩니다.</p>
      <Button size="sm" variant="solid" class="ml-auto" @click="openCreate">
        <UserPlus :size="14" /> 사용자 등록
      </Button>
    </div>

    <p v-if="notice" class="rounded-lg border border-success-border bg-success-soft px-3 py-2 text-sm text-success flex items-center">
      {{ notice }}
      <button class="ml-auto text-muted-foreground hover:text-foreground" aria-label="닫기" @click="notice = null"><X :size="14" /></button>
    </p>

    <DataState :loading="loading" :error="error" @retry="loadData" />

    <div v-if="!loading && !error" class="rounded-xl border border-border bg-card p-4">
      <h3 class="font-semibold text-sm mb-3">계정 목록 <span class="text-muted-foreground font-normal">({{ users.length }})</span></h3>
      <div class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead>
            <tr class="border-b border-border text-left text-muted-foreground">
              <th class="py-2 pr-3 font-medium">이메일</th>
              <th class="py-2 pr-3 font-medium">역할</th>
              <th class="py-2 pr-3 font-medium">최근 로그인</th>
              <th class="py-2 pr-3 font-medium">등록일</th>
              <th class="py-2 font-medium text-right">관리</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="u in sorted" :key="u.id" class="border-b border-border/50 hover:bg-accent/50">
              <td class="py-2.5 pr-3 font-medium">
                {{ u.email ?? '-' }}
                <span v-if="u.id === myId" class="ml-1 text-xs text-muted-foreground">(나)</span>
              </td>
              <td class="py-2.5 pr-3"><Badge :variant="roleVariant(u.role)">{{ roleLabel(u.role) }}</Badge></td>
              <td class="py-2.5 pr-3 text-muted-foreground">{{ u.last_sign_in_at ? formatWibShort(u.last_sign_in_at) : '-' }}</td>
              <td class="py-2.5 pr-3 text-muted-foreground">{{ formatWibShort(u.created_at) }}</td>
              <td class="py-2.5 text-right whitespace-nowrap">
                <Button size="sm" variant="ghost" :disabled="busy" @click="openPassword(u)">
                  <KeyRound :size="14" /> 비밀번호
                </Button>
                <Button size="sm" variant="ghost" class="text-destructive" :disabled="busy || u.id === myId" @click="remove(u)">
                  <Trash2 :size="14" /> 삭제
                </Button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- 등록 / 비밀번호 재설정 모달 -->
    <div v-if="mode" class="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4" @click.self="closeModal">
      <form class="w-full max-w-sm rounded-xl border border-border bg-card p-5 shadow-xl space-y-4" @submit.prevent="submit">
        <div class="flex items-center">
          <h3 class="font-semibold">{{ mode === 'create' ? '사용자 등록' : '비밀번호 재설정' }}</h3>
          <button type="button" class="ml-auto text-muted-foreground hover:text-foreground" aria-label="닫기" @click="closeModal"><X :size="16" /></button>
        </div>
        <p v-if="mode === 'password'" class="text-sm text-muted-foreground">{{ target?.email }}</p>

        <div class="form-grid">
          <template v-if="mode === 'create'">
            <div class="form-field">
              <label for="ua-email">이메일<span class="required">*</span></label>
              <input id="ua-email" v-model="fEmail" type="email" required autocomplete="off" placeholder="name@ptascendo.com" />
            </div>
            <div class="form-field">
              <label for="ua-role">역할<span class="required">*</span></label>
              <select id="ua-role" v-model="fRole">
                <option v-for="r in ROLE_OPTIONS" :key="r.value" :value="r.value">{{ r.label }}</option>
              </select>
            </div>
          </template>
          <div class="form-field">
            <label for="ua-pw">새 비밀번호</label>
            <input id="ua-pw" v-model="fPassword" type="password" autocomplete="new-password" placeholder="비워 두면 기본 비밀번호" />
          </div>
        </div>

        <p v-if="formError" class="rounded-lg border border-destructive/40 bg-destructive/5 px-3 py-2 text-sm text-destructive" role="alert">{{ formError }}</p>

        <div class="flex justify-end gap-2">
          <Button type="button" variant="outline" size="sm" @click="closeModal">취소</Button>
          <Button type="submit" variant="solid" size="sm" :disabled="busy">{{ mode === 'create' ? '등록' : '변경' }}</Button>
        </div>
      </form>
    </div>
  </div>
</template>
