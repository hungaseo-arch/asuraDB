<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import { Download, Calendar, LogIn, LogOut, Users } from 'lucide-vue-next';
import { fetchLoginHistory, type LoginHistoryRecord } from '@/lib/loginHistory';
import Button from '@/components/ui/Button.vue';
import Badge from '@/components/ui/Badge.vue';
import DataState from '@/components/ui/DataState.vue';
import PageHeader from '@/components/PageHeader.vue';

const loading = ref(true);
const error = ref<string | null>(null);
const records = ref<LoginHistoryRecord[]>([]);

const today   = new Date().toISOString().slice(0, 10);
const weekAgo = new Date(Date.now() - 6 * 86400000).toISOString().slice(0, 10);
const fromDate = ref(weekAgo);
const toDate   = ref(today);

async function loadData() {
  loading.value = true;
  error.value = null;
  try {
    records.value = await fetchLoginHistory({
      from: `${fromDate.value}T00:00:00`,
      to:   `${toDate.value}T23:59:59.999`,
    });
  } catch (e: any) {
    error.value = e.message || '데이터를 불러오지 못했습니다';
  } finally {
    loading.value = false;
  }
}

onMounted(loadData);
window.addEventListener('asura:refresh', loadData);

const loginCount  = computed(() => records.value.filter(r => r.event_type === 'login').length);
const logoutCount = computed(() => records.value.filter(r => r.event_type === 'logout').length);
const uniqueUsers = computed(() => new Set(records.value.map(r => r.user_id)).size);

function roleLabel(role: string | null) {
  return role === 'super_admin' ? 'Admin'
    : role === 'staff'       ? 'Staff'
    : role === 'distributor' ? 'Distributor'
    : role === 'end_user'    ? 'Customer'
    : '-';
}

function formatTime(iso: string) {
  return new Date(iso).toLocaleString('ko-KR', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' });
}

function exportCSV() {
  const rows = [['시간', '이메일', '역할', '유형']];
  for (const r of records.value) {
    rows.push([
      new Date(r.created_at).toLocaleString('ko-KR'),
      r.email ?? '-',
      roleLabel(r.role),
      r.event_type === 'login' ? '로그인' : '로그아웃',
    ]);
  }
  const csv = rows.map(r => r.map(c => `"${c}"`).join(',')).join('\n');
  const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `login_history_${fromDate.value}_${toDate.value}.csv`;
  a.click();
  URL.revokeObjectURL(url);
}
</script>

<template>
  <div class="p-4 sm:p-6 space-y-6">
    <PageHeader title="회원 로그 관리" desc="회원 로그인·로그아웃 이력을 조회합니다" />

    <!-- 기간 선택 + 액션 -->
    <div class="flex flex-wrap items-center gap-3">
      <div class="flex items-center gap-2">
        <Calendar :size="16" class="text-muted-foreground" />
        <input type="date" v-model="fromDate" @change="loadData" class="rounded-lg border border-border bg-card px-3 py-1.5 text-sm" />
        <span class="text-muted-foreground text-sm">~</span>
        <input type="date" v-model="toDate" @change="loadData" class="rounded-lg border border-border bg-card px-3 py-1.5 text-sm" />
      </div>
      <div class="flex gap-1 ml-auto">
        <Button size="sm" variant="outline" @click="exportCSV">
          <Download :size="14" class="mr-1" /> CSV 다운로드
        </Button>
      </div>
    </div>

    <DataState :loading="loading" :error="error" @retry="loadData" />

    <div v-if="!loading && !error" class="space-y-6">
      <!-- 요약 카드 -->
      <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
        <div class="rounded-xl border border-border bg-card p-4">
          <div class="flex items-center gap-2 text-muted-foreground text-xs mb-1"><LogIn :size="14" /> 로그인</div>
          <div class="text-2xl font-bold text-green-600">{{ loginCount }}</div>
        </div>
        <div class="rounded-xl border border-border bg-card p-4">
          <div class="flex items-center gap-2 text-muted-foreground text-xs mb-1"><LogOut :size="14" /> 로그아웃</div>
          <div class="text-2xl font-bold text-amber-600">{{ logoutCount }}</div>
        </div>
        <div class="rounded-xl border border-border bg-card p-4">
          <div class="flex items-center gap-2 text-muted-foreground text-xs mb-1"><Users :size="14" /> 순 방문자</div>
          <div class="text-2xl font-bold text-blue-600">{{ uniqueUsers }}</div>
        </div>
      </div>

      <!-- 상세 기록 -->
      <div class="rounded-xl border border-border bg-card p-4">
        <h3 class="font-semibold text-sm mb-3">상세 기록</h3>
        <div v-if="records.length === 0" class="text-sm text-muted-foreground py-4 text-center">
          기록이 없습니다
        </div>
        <div v-else class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-border text-left text-muted-foreground">
                <th class="py-2 pr-3 font-medium">시간</th>
                <th class="py-2 pr-3 font-medium">이메일</th>
                <th class="py-2 pr-3 font-medium">역할</th>
                <th class="py-2 font-medium">유형</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="rec in records" :key="rec.id" class="border-b border-border/50 hover:bg-accent/50">
                <td class="py-2.5 pr-3">{{ formatTime(rec.created_at) }}</td>
                <td class="py-2.5 pr-3 font-medium">{{ rec.email ?? '-' }}</td>
                <td class="py-2.5 pr-3 text-muted-foreground">{{ roleLabel(rec.role) }}</td>
                <td class="py-2.5">
                  <Badge :variant="rec.event_type === 'login' ? 'success' : 'default'">
                    {{ rec.event_type === 'login' ? '로그인' : '로그아웃' }}
                  </Badge>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </div>
</template>
