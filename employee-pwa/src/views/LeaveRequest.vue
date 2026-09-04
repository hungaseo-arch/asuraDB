<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { supabase } from '@/lib/supabase';
import { fetchEmployee, createLeaveRequest, fetchMyLeaveRequests } from '@/lib/attendance';

const router = useRouter();
const employee = ref<any>(null);
const leaveInfo = ref<any>(null);
const requests = ref<any[]>([]);
const loading = ref(true);

const leaveType = ref('annual');
const startDate = ref('');
const endDate = ref('');
const reason = ref('');
const submitting = ref(false);
const message = ref('');
const messageType = ref<'success' | 'error' | ''>('');

async function init() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) { router.push('/'); return; }
  try {
    employee.value = await fetchEmployee();
    const data = await fetchMyLeaveRequests();
    leaveInfo.value = data.employee;
    requests.value = data.requests;
  } catch (e) { /* ignore */ }
  loading.value = false;
}

onMounted(init);

const daysCount = ref(0);
function calcDays() {
  if (startDate.value && endDate.value) {
    const s = new Date(startDate.value);
    const e = new Date(endDate.value);
    daysCount.value = Math.ceil((e.getTime() - s.getTime()) / 86400000) + 1;
  }
}

async function submitLeave() {
  if (!startDate.value || !endDate.value || daysCount.value <= 0) {
    message.value = '날짜를 선택해주세요';
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
    const data = await fetchMyLeaveRequests();
    requests.value = data.requests;
    leaveInfo.value = data.employee;
  } catch (e: any) {
    message.value = '신청 실패: ' + (e.message || '오류');
    messageType.value = 'error';
  }
  submitting.value = false;
}

function statusLabel(s: string) {
  const m: Record<string, string> = { pending: '대기', approved: '승인', rejected: '거절', cancelled: '취소' };
  return m[s] ?? s;
}

function statusColor(s: string) {
  const m: Record<string, string> = { pending: 'text-amber-600 bg-amber-50', approved: 'text-green-600 bg-green-50', rejected: 'text-red-600 bg-red-50', cancelled: 'text-slate-500 bg-slate-100' };
  return m[s] ?? '';
}
</script>

<template>
  <div class="min-h-screen bg-slate-50 pb-20">
    <div class="bg-white border-b border-slate-200 px-4 py-3 flex items-center justify-between">
      <h1 class="font-bold text-lg">휴가 신청</h1>
      <button @click="router.push('/')" class="text-xs text-slate-400">← 돌아가기</button>
    </div>

    <div v-if="!loading" class="p-4 space-y-4">
      <!-- 잔여 연차 -->
      <div v-if="leaveInfo" class="bg-white rounded-2xl shadow-sm border border-slate-200 p-4">
        <div class="text-xs text-slate-500 mb-1">잔여 연차</div>
        <div class="text-2xl font-bold text-blue-600">{{ leaveInfo.annual_leave_total - leaveInfo.annual_leave_used }}일</div>
        <div class="text-xs text-slate-400 mt-1">전체 {{ leaveInfo.annual_leave_total }}일 중 {{ leaveInfo.annual_leave_used }}일 사용</div>
      </div>

      <!-- 신청 폼 -->
      <div class="bg-white rounded-2xl shadow-sm border border-slate-200 p-4 space-y-3">
        <h2 class="font-semibold text-sm">새 휴가 신청</h2>

        <div>
          <label class="text-xs text-slate-500">휴가 유형</label>
          <select v-model="leaveType" class="w-full mt-1 px-3 py-2.5 rounded-xl border border-slate-200 text-sm">
            <option value="annual">연차</option>
            <option value="sick">병가</option>
            <option value="personal">개인사유</option>
            <option value="other">기타</option>
          </select>
        </div>

        <div class="grid grid-cols-2 gap-3">
          <div>
            <label class="text-xs text-slate-500">시작일</label>
            <input v-model="startDate" type="date" @change="calcDays"
              class="w-full mt-1 px-3 py-2.5 rounded-xl border border-slate-200 text-sm" />
          </div>
          <div>
            <label class="text-xs text-slate-500">종료일</label>
            <input v-model="endDate" type="date" @change="calcDays"
              class="w-full mt-1 px-3 py-2.5 rounded-xl border border-slate-200 text-sm" />
          </div>
        </div>

        <div v-if="daysCount > 0" class="text-sm text-blue-600 font-medium">{{ daysCount }}일</div>

        <div>
          <label class="text-xs text-slate-500">사유</label>
          <textarea v-model="reason" rows="2" placeholder="사유를 입력하세요"
            class="w-full mt-1 px-3 py-2.5 rounded-xl border border-slate-200 text-sm resize-none"></textarea>
        </div>

        <div v-if="message" :class="['text-xs font-medium text-center py-2 rounded-xl',
          messageType === 'success' ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-700']">
          {{ message }}
        </div>

        <button @click="submitLeave" :disabled="submitting"
          class="w-full py-3 bg-blue-500 text-white rounded-xl font-semibold text-sm hover:bg-blue-600 disabled:opacity-50">
          {{ submitting ? '신청 중...' : '휴가 신청하기' }}
        </button>
      </div>

      <!-- 신청 내역 -->
      <div class="bg-white rounded-2xl shadow-sm border border-slate-200 p-4">
        <h2 class="font-semibold text-sm mb-3">신청 내역</h2>
        <div v-if="requests.length === 0" class="text-sm text-slate-400 text-center py-4">신청 내역이 없습니다</div>
        <div v-else class="space-y-2">
          <div v-for="req in requests" :key="req.id" class="border border-slate-100 rounded-xl p-3">
            <div class="flex items-center justify-between">
              <div>
                <span class="text-sm font-medium">{{ req.start_date }} ~ {{ req.end_date }}</span>
                <span class="text-xs text-slate-400 ml-2">{{ req.days_count }}일</span>
              </div>
              <span :class="['text-xs px-2 py-0.5 rounded-full font-medium', statusColor(req.status)]">
                {{ statusLabel(req.status) }}
              </span>
            </div>
            <div v-if="req.reason" class="text-xs text-slate-500 mt-1">{{ req.reason }}</div>
          </div>
        </div>
      </div>
    </div>

    <div v-else class="flex items-center justify-center py-20 text-slate-400">로딩 중...</div>

    <!-- 하단 메뉴 -->
    <div class="fixed bottom-0 left-0 right-0 bg-white border-t border-slate-200 flex">
      <button @click="router.push('/')" class="flex-1 py-3 flex flex-col items-center gap-0.5 text-slate-400">
        <span class="text-lg">🕐</span><span class="text-xs font-medium">출퇴근</span>
      </button>
      <button @click="router.push('/leave')" class="flex-1 py-3 flex flex-col items-center gap-0.5 text-blue-500">
        <span class="text-lg">📝</span><span class="text-xs font-medium">휴가</span>
      </button>
      <button @click="router.push('/history')" class="flex-1 py-3 flex flex-col items-center gap-0.5 text-slate-400">
        <span class="text-lg">📋</span><span class="text-xs font-medium">기록</span>
      </button>
    </div>
  </div>
</template>
