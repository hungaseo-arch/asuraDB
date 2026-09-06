<script setup lang="ts">
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { Download, Calendar, TrendingUp, Clock, UserCheck, UserX } from 'lucide-vue-next';
import {
  fetchEmployees, fetchAttendanceByDate, jakartaDate, formatJakartaTime,
  type Employee, type AttendanceRecord, type AttendanceStatus,
} from '@/lib/attendance';
import Button from '@/components/ui/Button.vue';
import Badge from '@/components/ui/Badge.vue';
import DataState from '@/components/ui/DataState.vue';
import PageHeader from '@/components/PageHeader.vue';
import { cn } from '@/lib/utils';

const loading = ref(true);
const error = ref<string | null>(null);
const employees = ref<Employee[]>([]);
const records = ref<AttendanceRecord[]>([]);
// 하루의 경계는 서버와 동일하게 Asia/Jakarta 기준
const selectedDate = ref(jakartaDate());
const viewMode = ref<'daily' | 'summary'>('daily');

async function loadData() {
  loading.value = true;
  error.value = null;
  try {
    const [emps, recs] = await Promise.all([
      fetchEmployees(),
      fetchAttendanceByDate(selectedDate.value),
    ]);
    employees.value = emps;
    records.value = recs;
  } catch (e: any) {
    error.value = e.message || '데이터를 불러오지 못했습니다';
  } finally {
    loading.value = false;
  }
}

onMounted(loadData);
window.addEventListener('asura:refresh', loadData);
onBeforeUnmount(() => window.removeEventListener('asura:refresh', loadData));

// 날짜 변경 시 다시 로드
async function onDateChange() {
  await loadData();
}

// ── 집계 (취소된 기록 제외) ──
const activeRecords = computed(() => records.value.filter(r => r.status !== 'voided'));

const checkedInIds = computed(() => {
  const ids = new Set(activeRecords.value.filter(r => r.check_type === 'check_in').map(r => r.employee_id));
  return ids;
});

const notCheckedIn = computed(() => employees.value.filter(e => !checkedInIds.value.has(e.id)));

const geoCompliant = computed(() => activeRecords.value.filter(r => r.is_within_geofence).length);

const totalChecks = computed(() => activeRecords.value.length);

// ── 상태·기기 표시 ──
type BadgeVariant = 'default' | 'secondary' | 'success' | 'warning' | 'info' | 'danger';
const STATUS_META: Record<AttendanceStatus, { label: string; variant: BadgeVariant }> = {
  normal:         { label: '정상',   variant: 'default' },
  belum_checkout: { label: '미퇴근', variant: 'warning' },
  corrected:      { label: '정정',   variant: 'info' },
  voided:         { label: '취소',   variant: 'secondary' },
};
function statusMeta(status: AttendanceStatus) {
  return STATUS_META[status] ?? STATUS_META.normal;
}

function deviceLabel(rec: AttendanceRecord): string {
  if (rec.device_id === 'manual') return '수기';
  return rec.device_info?.label ?? rec.device_id ?? '-';
}

function geofenceLabel(rec: AttendanceRecord): string {
  if (rec.latitude === null || rec.longitude === null) return '-'; // 수기 행은 좌표가 없어 판정 불가
  return rec.is_within_geofence ? '영역 내' : '영역 밖';
}

// ── 엑셀 다운로드 (취소된 기록도 상태=취소 로 포함) ──
function exportCSV() {
  const rows = [['직원명', '부서', '유형', '시간', '상태', '지오펜싱', '거리(m)', '기기', '정정 사유']];
  for (const r of records.value) {
    rows.push([
      r.employee?.name ?? '-',
      r.employee?.department ?? '-',
      r.check_type === 'check_in' ? '출근' : '퇴근',
      formatJakartaTime(r.check_time),
      statusMeta(r.status).label,
      geofenceLabel(r),
      r.distance_meters ? String(Math.round(r.distance_meters)) : '-',
      deviceLabel(r),
      r.correction_reason ?? '',
    ]);
  }
  const csv = rows.map(r => r.map(c => `"${String(c).replace(/"/g, '""')}"`).join(',')).join('\n');
  const blob = new Blob(['\uFEFF' + csv], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `attendance_${selectedDate.value}.csv`;
  a.click();
  URL.revokeObjectURL(url);
}

function formatTime(iso: string) {
  return iso ? formatJakartaTime(iso) : '-';
}
</script>

<template>
  <div class="p-4 sm:p-6 space-y-6">
    <PageHeader title="근태 보고서" desc="일자별 출퇴근 기록과 통계를 확인합니다 (자카르타 기준)" />

    <!-- 날짜 선택 + 액션 -->
    <div class="flex flex-wrap items-center gap-3">
      <div class="flex items-center gap-2">
        <Calendar :size="16" class="text-muted-foreground" />
        <input
          type="date"
          v-model="selectedDate"
          @change="onDateChange"
          class="rounded-lg border border-border bg-card px-3 py-1.5 text-sm"
        />
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
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div class="rounded-xl border border-border bg-card p-4">
          <div class="flex items-center gap-2 text-muted-foreground text-xs mb-1"><UserCheck :size="14" /> 출근</div>
          <div class="text-2xl font-bold text-green-600">{{ checkedInIds.size }}</div>
        </div>
        <div class="rounded-xl border border-border bg-card p-4">
          <div class="flex items-center gap-2 text-muted-foreground text-xs mb-1"><UserX :size="14" /> 미출근</div>
          <div class="text-2xl font-bold text-amber-600">{{ notCheckedIn.length }}</div>
        </div>
        <div class="rounded-xl border border-border bg-card p-4">
          <div class="flex items-center gap-2 text-muted-foreground text-xs mb-1"><TrendingUp :size="14" /> 전체 체크</div>
          <div class="text-2xl font-bold">{{ totalChecks }}</div>
        </div>
        <div class="rounded-xl border border-border bg-card p-4">
          <div class="flex items-center gap-2 text-muted-foreground text-xs mb-1"><Clock :size="14" /> 지오펜싱 준수</div>
          <div class="text-2xl font-bold text-blue-600">{{ geoCompliant }}</div>
        </div>
      </div>

      <!-- 출근자 / 미출근자 -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div class="rounded-xl border border-border bg-card p-4">
          <h3 class="font-semibold text-sm mb-3 text-green-600">출근자 ({{ checkedInIds.size }})</h3>
          <div v-if="checkedInIds.size === 0" class="text-sm text-muted-foreground">없음</div>
          <div v-else class="space-y-1.5">
            <div v-for="emp in employees.filter(e => checkedInIds.has(e.id))" :key="emp.id"
              class="flex items-center justify-between text-sm py-1">
              <span>{{ emp.name }} <span class="text-muted-foreground">· {{ emp.department }}</span></span>
              <span class="text-xs text-muted-foreground">
                {{ formatTime(activeRecords.find(r => r.employee_id === emp.id && r.check_type === 'check_in')?.check_time ?? '') }}
              </span>
            </div>
          </div>
        </div>
        <div class="rounded-xl border border-border bg-card p-4">
          <h3 class="font-semibold text-sm mb-3 text-amber-600">미출근자 ({{ notCheckedIn.length }})</h3>
          <div v-if="notCheckedIn.length === 0" class="text-sm text-muted-foreground">전원 출근</div>
          <div v-else class="space-y-1.5">
            <div v-for="emp in notCheckedIn" :key="emp.id"
              class="flex items-center text-sm py-1">
              <span>{{ emp.name }} <span class="text-muted-foreground">· {{ emp.department }}</span></span>
            </div>
          </div>
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
                <th class="py-2 pr-3 font-medium">직원</th>
                <th class="py-2 pr-3 font-medium">부서</th>
                <th class="py-2 pr-3 font-medium">유형</th>
                <th class="py-2 pr-3 font-medium">시간</th>
                <th class="py-2 pr-3 font-medium">상태</th>
                <th class="py-2 pr-3 font-medium">지오펜싱</th>
                <th class="py-2 pr-3 font-medium">거리</th>
                <th class="py-2 pr-3 font-medium">기기</th>
                <th class="py-2 font-medium">정정 사유</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="rec in records" :key="rec.id"
                :class="cn('border-b border-border/50 hover:bg-accent/50', rec.status === 'voided' && 'line-through opacity-60')"
              >
                <td class="py-2.5 pr-3 font-medium">{{ rec.employee?.name ?? '-' }}</td>
                <td class="py-2.5 pr-3 text-muted-foreground">{{ rec.employee?.department ?? '-' }}</td>
                <td class="py-2.5 pr-3">
                  <Badge :variant="rec.check_type === 'check_in' ? 'success' : 'default'">
                    {{ rec.check_type === 'check_in' ? '출근' : '퇴근' }}
                  </Badge>
                </td>
                <td class="py-2.5 pr-3 whitespace-nowrap">
                  <div>{{ formatTime(rec.check_time) }}</div>
                  <div v-if="rec.status === 'corrected' && rec.original_check_time" class="text-xs text-muted-foreground">
                    원래 {{ formatTime(rec.original_check_time) }}
                  </div>
                </td>
                <td class="py-2.5 pr-3">
                  <span v-if="rec.status === 'normal'" class="text-xs text-muted-foreground">정상</span>
                  <Badge v-else :variant="statusMeta(rec.status).variant">{{ statusMeta(rec.status).label }}</Badge>
                </td>
                <td class="py-2.5 pr-3">
                  <template v-if="rec.latitude === null || rec.longitude === null">-</template>
                  <template v-else>{{ rec.is_within_geofence ? '✅ 영역 내' : '⚠️ 영역 밖' }}</template>
                </td>
                <td class="py-2.5 pr-3">{{ rec.distance_meters ? Math.round(rec.distance_meters) + 'm' : '-' }}</td>
                <td class="py-2.5 pr-3 text-muted-foreground max-w-40 truncate" :title="rec.device_id ?? undefined">{{ deviceLabel(rec) }}</td>
                <td class="py-2.5 text-muted-foreground max-w-64">
                  <template v-if="rec.correction_reason">
                    {{ rec.correction_reason }}
                    <span v-if="rec.corrector?.name" class="text-xs">({{ rec.corrector.name }})</span>
                  </template>
                  <template v-else>-</template>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </div>
</template>
