<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import { fetchEmployee, createLeaveRequest, fetchMyLeaveRequests, type Employee, type LeaveRequest } from '@/lib/attendance';
import BottomNav from '@/components/BottomNav.vue';

const employee = ref<Employee | null>(null);
const requests = ref<LeaveRequest[]>([]);
const loading = ref(true);
const loadError = ref<string | null>(null);

const leaveType = ref('annual');
const startDate = ref('');
const endDate = ref('');
const reason = ref('');
const submitting = ref(false);
const message = ref('');
const messageType = ref<'success' | 'error' | ''>('');

async function init() {
  loading.value = true;
  loadError.value = null;
  try {
    const data = await fetchMyLeaveRequests();
    employee.value = data.employee ?? await fetchEmployee();
    requests.value = data.requests;
  } catch (e: any) {
    loadError.value = e.message || '휴가 정보를 불러오지 못했습니다';
  }
  loading.value = false;
}

onMounted(init);

const remaining = computed(() =>
  employee.value ? employee.value.annual_leave_total - employee.value.annual_leave_used : 0
);

// 근무일 기준 일수 — 주말(토·일)은 제외한다. 서버 트리거(leave_requests_validate)는
// 1 <= days_count <= 기간일수 만 검증하므로, 실제 차감 일수는 여기서 계산해 보낸다.
const daysCount = computed(() => {
  if (!startDate.value || !endDate.value) return 0;
  const s = new Date(`${startDate.value}T00:00:00Z`);
  const e = new Date(`${endDate.value}T00:00:00Z`);
  if (e < s) return 0;
  let n = 0;
  for (const d = new Date(s); d <= e; d.setUTCDate(d.getUTCDate() + 1)) {
    const wd = d.getUTCDay();
    if (wd !== 0 && wd !== 6) n++;
  }
  return n;
});

async function submitLeave() {
  if (!employee.value) {
    message.value = '직원 정보를 확인할 수 없습니다';
    messageType.value = 'error';
    return;
  }
  if (!startDate.value || !endDate.value) {
    message.value = '날짜를 선택해주세요';
    messageType.value = 'error';
    return;
  }
  if (daysCount.value <= 0) {
    message.value = '기간에 근무일이 없습니다 (주말 제외)';
    messageType.value = 'error';
    return;
  }
  submitting.value = true;
  try {
    await createLeaveRequest({
      employee_id: employee.value.id,
      leave_type: leaveType.value,
      start_date: startDate.value,
      end_date: endDate.value,
      days_count: daysCount.value,
      reason: reason.value,
    });
    message.value = '휴가 신청이 완료되었습니다';
    messageType.value = 'success';
    reason.value = '';
    const data = await fetchMyLeaveRequests();
    requests.value = data.requests;
    employee.value = data.employee ?? employee.value;
  } catch (e: any) {
    message.value = e.message || '신청에 실패했습니다';
    messageType.value = 'error';
  }
  submitting.value = false;
}

function statusLabel(s: string) {
  const m: Record<string, string> = { pending: '대기', approved: '승인', rejected: '거절', cancelled: '취소' };
  return m[s] ?? s;
}

function statusClass(s: string) {
  const m: Record<string, string> = {
    pending: 'text-warning bg-warning-soft',
    approved: 'text-success bg-success-soft',
    rejected: 'text-destructive bg-destructive-soft',
    cancelled: 'text-muted-foreground bg-secondary',
  };
  return m[s] ?? 'text-muted-foreground bg-secondary';
}

function typeLabel(t: string) {
  const m: Record<string, string> = { annual: '연차', sick: '병가', personal: '개인사유', other: '기타' };
  return m[t] ?? t;
}
</script>

<template>
  <div class="min-h-screen bg-background pb-20">
    <div class="bg-card border-b border-border px-4 py-3">
      <h1 class="font-bold text-lg">휴가 신청</h1>
    </div>

    <div v-if="loading" class="flex items-center justify-center py-20 text-muted-foreground">로딩 중...</div>
    <div v-else-if="loadError" class="m-4 bg-destructive-soft text-destructive rounded-xl p-4 text-sm text-center">
      {{ loadError }}
      <button @click="init" class="underline ml-1">다시 시도</button>
    </div>

    <div v-else class="p-4 space-y-4">
      <div v-if="employee" class="bg-card rounded-2xl border border-border p-4">
        <div class="text-xs text-muted-foreground mb-1">잔여 연차</div>
        <div class="text-2xl font-bold text-primary">{{ remaining }}일</div>
        <div class="text-xs text-muted-foreground mt-1">
          전체 {{ employee.annual_leave_total }}일 중 {{ employee.annual_leave_used }}일 사용
        </div>
      </div>

      <div class="bg-card rounded-2xl border border-border p-4 space-y-3">
        <h2 class="font-semibold text-sm">새 휴가 신청</h2>

        <div class="form-field">
          <label for="leaveType">휴가 유형<span class="required">*</span></label>
          <select id="leaveType" v-model="leaveType">
            <option value="annual">연차</option>
            <option value="sick">병가</option>
            <option value="personal">개인사유</option>
            <option value="other">기타</option>
          </select>
        </div>

        <div class="grid grid-cols-2 gap-3">
          <div class="form-field">
            <label for="startDate">시작일<span class="required">*</span></label>
            <input id="startDate" v-model="startDate" type="date" />
          </div>
          <div class="form-field">
            <label for="endDate">종료일<span class="required">*</span></label>
            <input id="endDate" v-model="endDate" type="date" />
          </div>
        </div>

        <div v-if="daysCount > 0" class="text-sm text-primary font-medium">
          {{ daysCount }}일 <span class="text-xs text-muted-foreground font-normal">(주말 제외)</span>
        </div>

        <div class="form-field">
          <label for="reason">사유</label>
          <textarea id="reason" v-model="reason" rows="2" placeholder="사유를 입력하세요" class="resize-none"></textarea>
        </div>

        <div v-if="message" :class="['text-xs font-medium text-center py-2 rounded-xl',
          messageType === 'success' ? 'bg-success-soft text-success' : 'bg-destructive-soft text-destructive']">
          {{ message }}
        </div>

        <button @click="submitLeave" :disabled="submitting" class="btn-primary text-sm">
          {{ submitting ? '신청 중...' : '휴가 신청하기' }}
        </button>
      </div>

      <div class="bg-card rounded-2xl border border-border p-4">
        <h2 class="font-semibold text-sm mb-3">신청 내역</h2>
        <div v-if="requests.length === 0" class="text-sm text-muted-foreground text-center py-4">신청 내역이 없습니다</div>
        <div v-else class="space-y-2">
          <div v-for="req in requests" :key="req.id" class="border border-border rounded-xl p-3">
            <div class="flex items-center justify-between">
              <div>
                <span class="text-sm font-medium">{{ req.start_date }} ~ {{ req.end_date }}</span>
                <span class="text-xs text-muted-foreground ml-2">{{ req.days_count }}일 · {{ typeLabel(req.leave_type) }}</span>
              </div>
              <span :class="['text-xs px-2 py-0.5 rounded-full font-medium', statusClass(req.status)]">
                {{ statusLabel(req.status) }}
              </span>
            </div>
            <div v-if="req.reason" class="text-xs text-muted-foreground mt-1">{{ req.reason }}</div>
          </div>
        </div>
      </div>
    </div>

    <BottomNav active="leave" />
  </div>
</template>
