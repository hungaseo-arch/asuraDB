<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import { Check, X, Calendar, Clock, User } from 'lucide-vue-next';
import { fetchLeaveRequests, fetchOvertimeRecords, updateLeaveStatus, updateOvertimeStatus, fetchEmployees, type LeaveRequest, type OvertimeRecord, type Employee } from '@/lib/attendance';
import Button from '@/components/ui/Button.vue';
import Badge from '@/components/ui/Badge.vue';
import DataState from '@/components/ui/DataState.vue';
import PageHeader from '@/components/PageHeader.vue';
import { cn } from '@/lib/utils';

const loading = ref(true);
const error = ref<string | null>(null);
const leaveRequests = ref<LeaveRequest[]>([]);
const overtimeRecords = ref<OvertimeRecord[]>([]);
const employees = ref<Employee[]>([]);
const activeTab = ref<'leave' | 'overtime'>('leave');

const statusFilter = ref<'all' | 'pending' | 'approved' | 'rejected'>('all');

async function loadData() {
  loading.value = true;
  error.value = null;
  try {
    const [leaves, overtimes, emps] = await Promise.all([
      fetchLeaveRequests(),
      fetchOvertimeRecords(),
      fetchEmployees(),
    ]);
    leaveRequests.value = leaves;
    overtimeRecords.value = overtimes;
    employees.value = emps;
  } catch (e: any) {
    error.value = e.message || '데이터를 불러오지 못했습니다';
  } finally {
    loading.value = false;
  }
}

onMounted(loadData);
window.addEventListener('asura:refresh', loadData);

const filteredLeaves = computed(() => {
  if (statusFilter.value === 'all') return leaveRequests.value;
  return leaveRequests.value.filter(l => l.status === statusFilter.value);
});

const filteredOvertimes = computed(() => {
  if (statusFilter.value === 'all') return overtimeRecords.value;
  return overtimeRecords.value.filter(o => o.status === statusFilter.value);
});

async function approveLeave(id: string) {
  const admin = employees.value.find(e => e.position === 'admin');
  if (!admin) { alert('관리자 정보를 찾을 수 없습니다'); return; }
  await updateLeaveStatus(id, 'approved', admin.id);
  await loadData();
}

async function rejectLeave(id: string) {
  const admin = employees.value.find(e => e.position === 'admin');
  if (!admin) { alert('관리자 정보를 찾을 수 없습니다'); return; }
  await updateLeaveStatus(id, 'rejected', admin.id);
  await loadData();
}

async function approveOvertime(id: string) {
  const admin = employees.value.find(e => e.position === 'admin');
  if (!admin) { alert('관리자 정보를 찾을 수 없습니다'); return; }
  await updateOvertimeStatus(id, 'approved', admin.id);
  await loadData();
}

async function rejectOvertime(id: string) {
  const admin = employees.value.find(e => e.position === 'admin');
  if (!admin) { alert('관리자 정보를 찾을 수 없습니다'); return; }
  await updateOvertimeStatus(id, 'rejected', admin.id);
  await loadData();
}

function statusBadge(status: string) {
  const map: Record<string, { variant: string; label: string }> = {
    pending: { variant: 'warning', label: '대기' },
    approved: { variant: 'success', label: '승인' },
    rejected: { variant: 'danger', label: '거절' },
    cancelled: { variant: 'default', label: '취소' },
  };
  return map[status] ?? { variant: 'default', label: status };
}

function leaveTypeLabel(type: string) {
  const map: Record<string, string> = { annual: '연차', sick: '병가', personal: '개인사유', other: '기타' };
  return map[type] ?? type;
}

function formatDate(date: string) {
  return new Date(date).toLocaleDateString('ko-KR', { month: 'long', day: 'numeric' });
}
</script>

<template>
  <div class="p-4 sm:p-6 space-y-6">
    <PageHeader title="휴가·연차 — 승인관리" desc="직원 휴가/연차 및 초과근무 신청을 승인·관리합니다" />

    <DataState :loading="loading" :error="error" @retry="loadData" />

    <div v-if="!loading && !error" class="space-y-6">
      <!-- 탭 -->
      <div class="flex gap-1 border-b border-border">
        <button
          :class="cn('px-4 py-2 text-sm font-medium border-b-2 transition-colors', activeTab === 'leave' ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground')"
          @click="activeTab = 'leave'"
        >휴가/연차 ({{ leaveRequests.length }})</button>
        <button
          :class="cn('px-4 py-2 text-sm font-medium border-b-2 transition-colors', activeTab === 'overtime' ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground')"
          @click="activeTab = 'overtime'"
        >초과근무 ({{ overtimeRecords.length }})</button>
      </div>

      <!-- 상태 필터 -->
      <div class="flex gap-2">
        <button v-for="f in [{k:'all',l:'전체'},{k:'pending',l:'대기'},{k:'approved',l:'승인'},{k:'rejected',l:'거절'}]" :key="f.k"
          :class="cn('px-3 py-1 text-xs rounded-full border transition-colors', statusFilter === f.k ? 'bg-primary text-primary-foreground border-primary' : 'border-border hover:bg-accent')"
          @click="statusFilter = f.k as any"
        >{{ f.l }}</button>
      </div>

      <!-- 휴가/연차 목록 -->
      <div v-if="activeTab === 'leave'">
        <div v-if="filteredLeaves.length === 0" class="text-sm text-muted-foreground py-8 text-center">
          신청 내역이 없습니다
        </div>
        <div v-else class="space-y-3">
          <div
            v-for="req in filteredLeaves" :key="req.id"
            class="rounded-xl border border-border bg-card p-4"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 mb-1">
                  <span class="font-semibold">{{ req.employee?.name ?? '-' }}</span>
                  <span class="text-xs text-muted-foreground">{{ req.employee?.department ?? '' }}</span>
                  <Badge :variant="statusBadge(req.status).variant as any">{{ statusBadge(req.status).label }}</Badge>
                </div>
                <div class="text-sm text-muted-foreground flex items-center gap-1.5">
                  <Calendar :size="13" /> {{ formatDate(req.start_date) }} ~ {{ formatDate(req.end_date) }}
                  <span class="mx-1">·</span>
                  {{ leaveTypeLabel(req.leave_type) }} · {{ req.days_count }}일
                </div>
                <div v-if="req.reason" class="text-sm mt-1.5 text-muted-foreground">사유: {{ req.reason }}</div>
              </div>
              <div v-if="req.status === 'pending'" class="flex gap-2 shrink-0">
                <Button size="sm" variant="outline" @click="rejectLeave(req.id)">
                  <X :size="14" class="mr-1" /> 거절
                </Button>
                <Button size="sm" @click="approveLeave(req.id)">
                  <Check :size="14" class="mr-1" /> 승인
                </Button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- 초과근무 목록 -->
      <div v-if="activeTab === 'overtime'">
        <div v-if="filteredOvertimes.length === 0" class="text-sm text-muted-foreground py-8 text-center">
          신청 내역이 없습니다
        </div>
        <div v-else class="space-y-3">
          <div
            v-for="rec in filteredOvertimes" :key="rec.id"
            class="rounded-xl border border-border bg-card p-4"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 mb-1">
                  <span class="font-semibold">{{ rec.employee?.name ?? '-' }}</span>
                  <span class="text-xs text-muted-foreground">{{ rec.employee?.department ?? '' }}</span>
                  <Badge :variant="statusBadge(rec.status).variant as any">{{ statusBadge(rec.status).label }}</Badge>
                </div>
                <div class="text-sm text-muted-foreground flex items-center gap-1.5">
                  <Calendar :size="13" /> {{ formatDate(rec.overtime_date) }}
                  <span class="mx-1">·</span>
                  <Clock :size="13" /> {{ rec.start_time }} ~ {{ rec.end_time }} · {{ rec.hours }}시간
                </div>
                <div v-if="rec.reason" class="text-sm mt-1.5 text-muted-foreground">사유: {{ rec.reason }}</div>
              </div>
              <div v-if="rec.status === 'pending'" class="flex gap-2 shrink-0">
                <Button size="sm" variant="outline" @click="rejectOvertime(rec.id)">
                  <X :size="14" class="mr-1" /> 거절
                </Button>
                <Button size="sm" @click="approveOvertime(rec.id)">
                  <Check :size="14" class="mr-1" /> 승인
                </Button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
