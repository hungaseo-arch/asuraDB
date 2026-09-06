<script setup lang="ts">
import { ref, onMounted, computed } from 'vue';
import { fetchMyAttendance, type AttendanceRecord } from '@/lib/attendance';
import { jakartaMonth, jakartaMonthRange, jakartaDate, formatJakartaTime, formatJakartaDateShort } from '@/lib/date';
import BottomNav from '@/components/BottomNav.vue';

const records = ref<AttendanceRecord[]>([]);
const loading = ref(true);
const error = ref<string | null>(null);
const selectedMonth = ref(jakartaMonth());

async function loadData() {
  loading.value = true;
  error.value = null;
  try {
    const { from, to } = jakartaMonthRange(selectedMonth.value);
    records.value = await fetchMyAttendance(from, to);
  } catch (e: any) {
    error.value = e.message || '기록을 불러오지 못했습니다';
    records.value = [];
  }
  loading.value = false;
}

onMounted(loadData);

// 취소(voided) 기록은 통계에서 제외한다(목록에는 취소 표시와 함께 남긴다).
const activeRecords = computed(() => records.value.filter(r => r.status !== 'voided'));

// 날짜별 그룹핑 — 서버와 같은 자카르타 기준으로 묶는다.
const groupedByDate = computed(() => {
  const map: Record<string, AttendanceRecord[]> = {};
  for (const r of records.value) {
    const date = jakartaDate(new Date(r.check_time));
    (map[date] ??= []).push(r);
  }
  return Object.entries(map).sort((a, b) => b[0].localeCompare(a[0]));
});

const workDays = computed(() =>
  new Set(activeRecords.value.filter(r => r.check_type === 'check_in').map(r => jakartaDate(new Date(r.check_time)))).size
);

function getWorkHours(dayRecords: AttendanceRecord[]): string {
  const active = dayRecords.filter(r => r.status !== 'voided');
  const checkIn = active.find(r => r.check_type === 'check_in');
  const checkOut = active.find(r => r.check_type === 'check_out');
  if (!checkIn || !checkOut) return '-';
  const diff = new Date(checkOut.check_time).getTime() - new Date(checkIn.check_time).getTime();
  if (diff <= 0) return '-';
  const h = Math.floor(diff / 3600000);
  const m = Math.floor((diff % 3600000) / 60000);
  return `${h}h ${m}m`;
}

const STATUS_LABEL: Record<string, string> = {
  belum_checkout: '미퇴근',
  corrected: '정정',
  voided: '취소',
};
</script>

<template>
  <div class="min-h-screen bg-background pb-20">
    <div class="bg-card border-b border-border px-4 py-3">
      <h1 class="font-bold text-lg">근태 기록</h1>
      <p class="text-xs text-muted-foreground">자카르타 시간 기준</p>
    </div>

    <div class="p-4 space-y-4">
      <div class="form-field">
        <label for="month">조회 월</label>
        <input id="month" type="month" v-model="selectedMonth" @change="loadData" />
      </div>

      <div class="grid grid-cols-3 gap-3">
        <div class="bg-card rounded-xl border border-border p-3 text-center">
          <div class="text-xs text-muted-foreground">근무일</div>
          <div class="text-xl font-bold text-primary">{{ workDays }}</div>
        </div>
        <div class="bg-card rounded-xl border border-border p-3 text-center">
          <div class="text-xs text-muted-foreground">지오펜싱</div>
          <div class="text-xl font-bold text-success">{{ activeRecords.filter(r => r.is_within_geofence).length }}</div>
        </div>
        <div class="bg-card rounded-xl border border-border p-3 text-center">
          <div class="text-xs text-muted-foreground">전체</div>
          <div class="text-xl font-bold">{{ activeRecords.length }}</div>
        </div>
      </div>

      <div v-if="loading" class="text-center py-10 text-muted-foreground">로딩 중...</div>
      <div v-else-if="error" class="bg-destructive-soft text-destructive rounded-xl p-4 text-sm text-center">
        {{ error }}
        <button @click="loadData" class="underline ml-1">다시 시도</button>
      </div>
      <div v-else-if="groupedByDate.length === 0" class="text-center py-10 text-muted-foreground">
        {{ selectedMonth }} 기록이 없습니다
      </div>
      <div v-else class="space-y-3">
        <div v-for="[date, dayRecords] in groupedByDate" :key="date"
          class="bg-card rounded-xl border border-border p-3">
          <div class="flex items-center justify-between mb-2">
            <span class="text-sm font-semibold">{{ formatJakartaDateShort(date) }}</span>
            <span class="text-xs text-muted-foreground">근무 {{ getWorkHours(dayRecords) }}</span>
          </div>
          <div class="space-y-1">
            <div v-for="rec in dayRecords" :key="rec.id"
              :class="['flex items-center justify-between text-xs py-1', rec.status === 'voided' ? 'line-through opacity-60' : '']">
              <div class="flex items-center gap-2">
                <span :class="rec.check_type === 'check_in' ? 'text-success' : 'text-primary'">
                  {{ rec.check_type === 'check_in' ? '출근' : '퇴근' }}
                </span>
                <span class="text-muted-foreground">{{ formatJakartaTime(rec.check_time) }}</span>
                <span v-if="STATUS_LABEL[rec.status]" class="px-1.5 py-0.5 rounded bg-secondary text-muted-foreground"
                  :title="rec.correction_reason ?? ''">
                  {{ STATUS_LABEL[rec.status] }}
                </span>
              </div>
              <span :class="rec.is_within_geofence ? 'text-success' : 'text-warning'">
                {{ rec.distance_meters === null ? '기록 없음' : (rec.is_within_geofence ? '✅ 영역 내' : '⚠️ 영역 밖') }}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <BottomNav active="history" />
  </div>
</template>
