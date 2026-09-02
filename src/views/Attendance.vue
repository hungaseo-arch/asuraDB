<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue';
import { MapPin, Users, Clock, CheckCircle2, XCircle, AlertTriangle, RefreshCw, Plus, Pencil, Trash2 } from 'lucide-vue-next';
import { fetchEmployees, fetchGeofenceZones, fetchTodayAttendance, createGeofenceZone, updateGeofenceZone, deleteGeofenceZone, type Employee, type GeofenceZone, type AttendanceRecord } from '@/lib/attendance';
import Button from '@/components/ui/Button.vue';
import Input from '@/components/ui/Input.vue';
import Badge from '@/components/ui/Badge.vue';
import DataState from '@/components/ui/DataState.vue';
import PageHeader from '@/components/PageHeader.vue';
import { cn } from '@/lib/utils';

// ── 상태 ──
const loading = ref(true);
const error = ref<string | null>(null);
const employees = ref<Employee[]>([]);
const zones = ref<GeofenceZone[]>([]);
const todayRecords = ref<AttendanceRecord[]>([]);
const selectedZone = ref<GeofenceZone | null>(null);
const showZoneModal = ref(false);
const zoneForm = ref({ name: '', description: '', latitude: 37.5665, longitude: 126.9780, radius_meters: 100 });
const editingZoneId = ref<string | null>(null);

// ── 데이터 로드 ──
async function loadData() {
  loading.value = true;
  error.value = null;
  try {
    const [emp, zn, rec] = await Promise.all([
      fetchEmployees(),
      fetchGeofenceZones(),
      fetchTodayAttendance(),
    ]);
    employees.value = emp;
    zones.value = zn;
    todayRecords.value = rec;
  } catch (e: any) {
    error.value = e.message || '데이터를 불러오지 못했습니다';
  } finally {
    loading.value = false;
  }
}

onMounted(loadData);
window.addEventListener('asura:refresh', loadData);

// ── 통계 ──
const checkedInCount = computed(() => {
  const empIds = new Set(todayRecords.value.filter(r => r.check_type === 'check_in').map(r => r.employee_id));
  return empIds.size;
});

const geoCount = computed(() => todayRecords.value.filter(r => r.is_within_geofence).length);
const totalEmployees = computed(() => employees.value.length);

// ── 지오펜싱 영역 관리 ──
function openAddZone() {
  editingZoneId.value = null;
  zoneForm.value = { name: '', description: '', latitude: 37.5665, longitude: 126.9780, radius_meters: 100 };
  showZoneModal.value = true;
}

function openEditZone(zone: GeofenceZone) {
  editingZoneId.value = zone.id;
  zoneForm.value = {
    name: zone.name,
    description: zone.description || '',
    latitude: zone.latitude,
    longitude: zone.longitude,
    radius_meters: zone.radius_meters,
  };
  showZoneModal.value = true;
}

async function saveZone() {
  try {
    if (editingZoneId.value) {
      await updateGeofenceZone(editingZoneId.value, zoneForm.value);
    } else {
      await createGeofenceZone(zoneForm.value);
    }
    showZoneModal.value = false;
    await loadData();
  } catch (e: any) {
    alert('저장 실패: ' + (e.message || '알 수 없는 오류'));
  }
}

async function removeZone(id: string) {
  if (!confirm('이 지오펜싱 영역을 비활성화하시겠습니까?')) return;
  await deleteGeofenceZone(id);
  await loadData();
}

// ── 시간 포맷 ──
function formatTime(iso: string) {
  return new Date(iso).toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit' });
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString('ko-KR', { month: 'long', day: 'numeric', weekday: 'short' });
}
</script>

<template>
  <div class="p-4 sm:p-6 space-y-6">
    <PageHeader title="근태 — 출퇴근관리" desc="직원 출퇴근 현황과 지오펜싱 영역을 관리합니다" />

    <DataState :loading="loading" :error="error" @retry="loadData" />

    <div v-if="!loading && !error" class="space-y-6">
      <!-- 통계 카드 -->
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div class="rounded-xl border border-border bg-card p-4">
          <div class="flex items-center gap-2 text-muted-foreground text-xs mb-1"><Users :size="14" /> 전체 직원</div>
          <div class="text-2xl font-bold">{{ totalEmployees }}</div>
        </div>
        <div class="rounded-xl border border-border bg-card p-4">
          <div class="flex items-center gap-2 text-muted-foreground text-xs mb-1"><CheckCircle2 :size="14" /> 오늘 출근</div>
          <div class="text-2xl font-bold text-green-600">{{ checkedInCount }}</div>
        </div>
        <div class="rounded-xl border border-border bg-card p-4">
          <div class="flex items-center gap-2 text-muted-foreground text-xs mb-1"><MapPin :size="14" /> 지오펜싱 내</div>
          <div class="text-2xl font-bold text-blue-600">{{ geoCount }}</div>
        </div>
        <div class="rounded-xl border border-border bg-card p-4">
          <div class="flex items-center gap-2 text-muted-foreground text-xs mb-1"><Clock :size="14" /> 미출근</div>
          <div class="text-2xl font-bold text-amber-600">{{ totalEmployees - checkedInCount }}</div>
        </div>
      </div>

      <!-- 지오펜싱 영역 + 지도 -->
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <!-- 영역 목록 -->
        <div class="rounded-xl border border-border bg-card p-4 lg:col-span-1">
          <div class="flex items-center justify-between mb-3">
            <h2 class="font-semibold text-sm">지오펜싱 영역</h2>
            <Button size="sm" variant="outline" @click="openAddZone">
              <Plus :size="14" class="mr-1" /> 추가
            </Button>
          </div>
          <div v-if="zones.length === 0" class="text-sm text-muted-foreground py-4 text-center">
            등록된 지오펜싱 영역이 없습니다
          </div>
          <div v-else class="space-y-2">
            <div
              v-for="zone in zones" :key="zone.id"
              :class="cn(
                'rounded-lg border p-3 cursor-pointer transition-colors',
                selectedZone?.id === zone.id ? 'border-primary bg-primary/5' : 'border-border hover:bg-accent'
              )"
              @click="selectedZone = selectedZone?.id === zone.id ? null : zone"
            >
              <div class="flex items-center justify-between">
                <div>
                  <div class="font-medium text-sm">{{ zone.name }}</div>
                  <div class="text-xs text-muted-foreground mt-0.5">
                    반경 {{ zone.radius_meters }}m · {{ zone.latitude.toFixed(4) }}, {{ zone.longitude.toFixed(4) }}
                  </div>
                </div>
                <div class="flex gap-1">
                  <button class="p-1 hover:bg-accent rounded" title="수정" @click.stop="openEditZone(zone)">
                    <Pencil :size="13" />
                  </button>
                  <button class="p-1 hover:bg-accent rounded text-red-500" title="삭제" @click.stop="removeZone(zone.id)">
                    <Trash2 :size="13" />
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- 미니 지도 -->
        <div class="rounded-xl border border-border bg-card overflow-hidden lg:col-span-2" style="min-height: 320px;">
          <div id="attendance-map" class="w-full h-full" style="min-height: 320px;"></div>
        </div>
      </div>

      <!-- 오늘 출퇴근 기록 -->
      <div class="rounded-xl border border-border bg-card p-4">
        <h2 class="font-semibold text-sm mb-3">{{ formatDate(new Date().toISOString()) }} 출퇴근 기록</h2>
        <div v-if="todayRecords.length === 0" class="text-sm text-muted-foreground py-4 text-center">
          오늘 출퇴근 기록이 없습니다
        </div>
        <div v-else class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-border text-left text-muted-foreground">
                <th class="py-2 pr-3 font-medium">직원</th>
                <th class="py-2 pr-3 font-medium">부서</th>
                <th class="py-2 pr-3 font-medium">유형</th>
                <th class="py-2 pr-3 font-medium">시간</th>
                <th class="py-2 pr-3 font-medium">지오펜싱</th>
                <th class="py-2 font-medium">거리</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="rec in todayRecords" :key="rec.id" class="border-b border-border/50 hover:bg-accent/50">
                <td class="py-2.5 pr-3 font-medium">{{ rec.employee?.name ?? '-' }}</td>
                <td class="py-2.5 pr-3 text-muted-foreground">{{ rec.employee?.department ?? '-' }}</td>
                <td class="py-2.5 pr-3">
                  <Badge :variant="rec.check_type === 'check_in' ? 'success' : 'default'">
                    {{ rec.check_type === 'check_in' ? '출근' : '퇴근' }}
                  </Badge>
                </td>
                <td class="py-2.5 pr-3">{{ formatTime(rec.check_time) }}</td>
                <td class="py-2.5 pr-3">
                  <span v-if="rec.is_within_geofence" class="text-green-600 flex items-center gap-1">
                    <CheckCircle2 :size="13" /> {{ rec.geofence_zone?.name ?? '영역 내' }}
                  </span>
                  <span v-else class="text-amber-600 flex items-center gap-1">
                    <AlertTriangle :size="13" /> 영역 밖
                  </span>
                </td>
                <td class="py-2.5">{{ rec.distance_meters ? Math.round(rec.distance_meters) + 'm' : '-' }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- 지오펜싱 영역 추가/수정 모달 -->
    <div v-if="showZoneModal" class="fixed inset-0 z-50 flex items-center justify-center bg-black/40" @click.self="showZoneModal = false">
      <div class="bg-card rounded-xl border border-border shadow-2xl p-6 w-full max-w-md mx-4">
        <h3 class="font-semibold text-lg mb-4">{{ editingZoneId ? '영역 수정' : '새 지오펜싱 영역' }}</h3>
        <div class="space-y-3">
          <div>
            <label class="text-xs font-medium text-muted-foreground">이름</label>
            <Input v-model="zoneForm.name" placeholder="예: 본사" class="mt-1" />
          </div>
          <div>
            <label class="text-xs font-medium text-muted-foreground">설명</label>
            <Input v-model="zoneForm.description" placeholder="설명 (선택)" class="mt-1" />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-medium text-muted-foreground">위도</label>
              <Input v-model.number="zoneForm.latitude" type="number" step="0.0001" class="mt-1" />
            </div>
            <div>
              <label class="text-xs font-medium text-muted-foreground">경도</label>
              <Input v-model.number="zoneForm.longitude" type="number" step="0.0001" class="mt-1" />
            </div>
          </div>
          <div>
            <label class="text-xs font-medium text-muted-foreground">반경 (미터)</label>
            <Input v-model.number="zoneForm.radius_meters" type="number" min="10" max="10000" class="mt-1" />
          </div>
        </div>
        <div class="flex justify-end gap-2 mt-5">
          <Button variant="outline" @click="showZoneModal = false">취소</Button>
          <Button @click="saveZone" :disabled="!zoneForm.name">{{ editingZoneId ? '저장' : '추가' }}</Button>
        </div>
      </div>
    </div>
  </div>
</template>
