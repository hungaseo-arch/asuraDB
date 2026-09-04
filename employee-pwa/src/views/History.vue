<script setup lang="ts">
import { ref, onMounted, computed } from 'vue';
import { useRouter } from 'vue-router';
import { supabase } from '@/lib/supabase';
import { fetchMyAttendance, fetchEmployee, type AttendanceRecord } from '@/lib/attendance';

const router = useRouter();
const records = ref<AttendanceRecord[]>([]);
const loading = ref(true);
const employee = ref<any>(null);

const selectedMonth = ref(new Date().toISOString().slice(0, 7));

async function loadData() {
  loading.value = true;
  try {
    employee.value = await fetchEmployee();
    const [year, month] = selectedMonth.value.split('-');
    const lastDay = new Date(Number(year), Number(month), 0).getDate();
    const from = `${selectedMonth.value}-01T00:00:00`;
    const to = `${selectedMonth.value}-${String(lastDay).padStart(2, '0')}T23:59:59`;
    records.value = await fetchMyAttendance(from, to);
  } catch (e) { /* ignore */ }
  loading.value = false;
}

onMounted(loadData);

// 날짜별 그룹핑
const groupedByDate = computed(() => {
  const map: Record<string, AttendanceRecord[]> = {};
  for (const r of records.value) {
    const date = r.check_time.slice(0, 10);
    if (!map[date]) map[date] = [];
    map[date].push(r);
  }
  return Object.entries(map).sort((a, b) => b[0].localeCompare(a[0]));
});

function formatTime(iso: string) {
  return new Date(iso).toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit' });
}

function formatDateShort(date: string) {
  const d = new Date(date);
  return `${d.getMonth() + 1}/${d.getDate()} (${['일','월','화','수','목','금','토'][d.getDay()]})`;
}

function getWorkHours(dayRecords: AttendanceRecord[]): string {
  const checkIn = dayRecords.find(r => r.check_type === 'check_in');
  const checkOut = dayRecords.find(r => r.check_type === 'check_out');
  if (!checkIn || !checkOut) return '-';
  const diff = new Date(checkOut.check_time).getTime() - new Date(checkIn.check_time).getTime();
  const h = Math.floor(diff / 3600000);
  const m = Math.floor((diff % 3600000) / 60000);
  return `${h}h ${m}m`;
}
</script>

<template>
  <div class="min-h-screen bg-slate-50 pb-20">
    <div class="bg-white border-b border-slate-200 px-4 py-3 flex items-center justify-between">
      <h1 class="font-bold text-lg">근태 기록</h1>
      <button @click="router.push('/')" class="text-xs text-slate-400">← 돌아가기</button>
    </div>

    <div class="p-4 space-y-4">
      <!-- 월 선택 -->
      <div class="flex items-center gap-2">
        <input type="month" v-model="selectedMonth" @change="loadData"
          class="px-3 py-2 rounded-xl border border-slate-200 text-sm" />
      </div>

      <!-- 요약 -->
      <div class="grid grid-cols-3 gap-3">
        <div class="bg-white rounded-xl border border-slate-200 p-3 text-center">
          <div class="text-xs text-slate-500">근무일</div>
          <div class="text-xl font-bold text-blue-600">{{ groupedByDate.length }}</div>
        </div>
        <div class="bg-white rounded-xl border border-slate-200 p-3 text-center">
          <div class="text-xs text-slate-500">지오펜싱</div>
          <div class="text-xl font-bold text-green-600">{{ records.filter(r => r.is_within_geofence).length }}</div>
        </div>
        <div class="bg-white rounded-xl border border-slate-200 p-3 text-center">
          <div class="text-xs text-slate-500">전체</div>
          <div class="text-xl font-bold">{{ records.length }}</div>
        </div>
      </div>

      <!-- 기록 목록 -->
      <div v-if="loading" class="text-center py-10 text-slate-400">로딩 중...</div>
      <div v-else-if="groupedByDate.length === 0" class="text-center py-10 text-slate-400">
        {{ selectedMonth }} 기록이 없습니다
      </div>
      <div v-else class="space-y-3">
        <div v-for="[date, dayRecords] in groupedByDate" :key="date"
          class="bg-white rounded-xl border border-slate-200 p-3">
          <div class="flex items-center justify-between mb-2">
            <span class="text-sm font-semibold">{{ formatDateShort(date) }}</span>
            <span class="text-xs text-slate-500">근무 {{ getWorkHours(dayRecords) }}</span>
          </div>
          <div class="space-y-1">
            <div v-for="rec in dayRecords" :key="rec.id"
              class="flex items-center justify-between text-xs py-1">
              <div class="flex items-center gap-2">
                <span :class="rec.check_type === 'check_in' ? 'text-green-600' : 'text-blue-600'">
                  {{ rec.check_type === 'check_in' ? '출근' : '퇴근' }}
                </span>
                <span class="text-slate-500">{{ formatTime(rec.check_time) }}</span>
              </div>
              <span :class="rec.is_within_geofence ? 'text-green-500' : 'text-amber-500'">
                {{ rec.is_within_geofence ? '✅ 영역 내' : '⚠️ 영역 밖' }}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- 하단 메뉴 -->
    <div class="fixed bottom-0 left-0 right-0 bg-white border-t border-slate-200 flex">
      <button @click="router.push('/')" class="flex-1 py-3 flex flex-col items-center gap-0.5 text-slate-400">
        <span class="text-lg">🕐</span><span class="text-xs font-medium">출퇴근</span>
      </button>
      <button @click="router.push('/leave')" class="flex-1 py-3 flex flex-col items-center gap-0.5 text-slate-400">
        <span class="text-lg">📝</span><span class="text-xs font-medium">휴가</span>
      </button>
      <button @click="router.push('/history')" class="flex-1 py-3 flex flex-col items-center gap-0.5 text-blue-500">
        <span class="text-lg">📋</span><span class="text-xs font-medium">기록</span>
      </button>
    </div>
  </div>
</template>
