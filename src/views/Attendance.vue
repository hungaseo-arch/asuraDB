<script setup lang="ts">
import { ref, computed, onMounted, onBeforeUnmount, watch, nextTick } from 'vue';
import { MapPin, Users, Clock, CheckCircle2, AlertTriangle, Plus, Pencil, Trash2, Smartphone, Bell, Camera } from 'lucide-vue-next';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png';
import markerIcon from 'leaflet/dist/images/marker-icon.png';
import markerShadow from 'leaflet/dist/images/marker-shadow.png';
import {
  fetchEmployees, fetchGeofenceZones, fetchTodayAttendance, createGeofenceZone, updateGeofenceZone, deleteGeofenceZone,
  fetchEmployeeByUserId, fetchEmployeeDevices, approveDevice, revokeDevice, fetchGeofenceAlerts, acknowledgeAlert,
  correctAttendance, addManualAttendance, voidAttendance, getSelfieSignedUrl,
  jakartaDate, formatJakartaTime, formatJakartaDateTime, toJakartaLocalInput, fromJakartaLocalInput,
  type Employee, type GeofenceZone, type AttendanceRecord, type AttendanceStatus, type EmployeeDevice, type GeofenceAlert,
} from '@/lib/attendance';
import { supabase } from '@/lib/supabase';
import Button from '@/components/ui/Button.vue';
import Input from '@/components/ui/Input.vue';
import Badge from '@/components/ui/Badge.vue';
import DataState from '@/components/ui/DataState.vue';
import PageHeader from '@/components/PageHeader.vue';
import { cn } from '@/lib/utils';

// 번들러 환경에서 Leaflet 기본 마커 아이콘 경로가 깨지는 문제 — 아이콘을 직접 지정해야 한다.
L.Icon.Default.mergeOptions({
  iconRetinaUrl: markerIcon2x,
  iconUrl: markerIcon,
  shadowUrl: markerShadow,
});

// HR 보정(정정·수기 추가·취소)·기기 승인·알림 확인은 super_admin 전용.
// ※ 화면 숨김은 표시 제어일 뿐이며 실제 차단은 RPC 의 역할 검사와 RLS 가 담당한다(attendance_antifraud_phase2_1.sql).
const isSuperAdmin = sessionStorage.getItem('asura_auth') === 'super_admin';

// ── 상태 ──
const loading = ref(true);
const error = ref<string | null>(null);
const employees = ref<Employee[]>([]);
const zones = ref<GeofenceZone[]>([]);
const todayRecords = ref<AttendanceRecord[]>([]);
const selectedZone = ref<GeofenceZone | null>(null);
const showZoneModal = ref(false);
const zoneForm = ref({ name: '', description: '', latitude: -6.2088, longitude: 106.8456, radius_meters: 100 });
const editingZoneId = ref<string | null>(null);

// 기기 승인 / 이탈 알림 — 각자 오류를 갖고, 본문 전체를 가리지 않는다
const devices = ref<EmployeeDevice[]>([]);
const devicesError = ref<string | null>(null);
const alerts = ref<GeofenceAlert[]>([]);
const alertsError = ref<string | null>(null);

// 관리자의 employees.id (알림 확인자 기록용). 직원과 연결되지 않은 관리자면 null.
const adminEmployeeId = ref<string | null>(null);

// ── 지도 ──
let map: L.Map | null = null;
const zoneLayers = new Map<string, { marker: L.Marker; circle: L.Circle }>();

function renderZones() {
  if (!map) return;
  for (const { marker, circle } of zoneLayers.values()) { marker.remove(); circle.remove(); }
  zoneLayers.clear();
  for (const zone of zones.value) {
    const popupEl = document.createElement('span');
    popupEl.textContent = zone.name;
    const marker = L.marker([zone.latitude, zone.longitude]).addTo(map).bindPopup(popupEl);
    const circle = L.circle([zone.latitude, zone.longitude], { radius: zone.radius_meters, color: '#546E7A', fillOpacity: 0.12 }).addTo(map);
    zoneLayers.set(zone.id, { marker, circle });
  }
  if (zones.value.length) {
    const bounds = L.latLngBounds(zones.value.map(z => [z.latitude, z.longitude] as [number, number]));
    map.fitBounds(bounds.pad(0.3), { maxZoom: 15 });
  }
}

function initMap() {
  const el = document.getElementById('attendance-map');
  if (!el || map) return;
  map = L.map(el).setView([-6.2088, 106.8456], 11); // 기본 중심: 자카르타
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
    maxZoom: 19,
  }).addTo(map);
  renderZones();
}

watch(zones, () => { if (map) renderZones(); else nextTick(initMap); });

watch(selectedZone, (zone) => {
  if (!map || !zone) return;
  map.flyTo([zone.latitude, zone.longitude], 16);
  zoneLayers.get(zone.id)?.marker.openPopup();
});

// ── 데이터 로드 ──
async function loadDevices() {
  devicesError.value = null;
  try {
    devices.value = await fetchEmployeeDevices();
  } catch (e: any) {
    devicesError.value = e.message || '기기 목록을 불러오지 못했습니다';
  }
}

async function loadAlerts() {
  alertsError.value = null;
  try {
    alerts.value = await fetchGeofenceAlerts(jakartaDate());
  } catch (e: any) {
    alertsError.value = e.message || '이탈 알림을 불러오지 못했습니다';
  }
}

async function loadData() {
  loading.value = true;
  error.value = null;
  try {
    const [emp, zn, rec] = await Promise.all([
      fetchEmployees(),
      fetchGeofenceZones(),
      fetchTodayAttendance(),
      loadDevices(), // 자체 try/catch — 실패해도 본문은 그대로 그린다
      loadAlerts(),
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

async function loadAdminEmployeeId() {
  try {
    const { data } = await supabase.auth.getUser();
    if (!data.user) return;
    adminEmployeeId.value = (await fetchEmployeeByUserId(data.user.id))?.id ?? null;
  } catch {
    adminEmployeeId.value = null; // 직원 미연결 관리자 — 확인자 없이 acknowledged 만 기록
  }
}

onMounted(() => { loadData(); loadAdminEmployeeId(); });
window.addEventListener('asura:refresh', loadData);
onBeforeUnmount(() => {
  window.removeEventListener('asura:refresh', loadData);
  map?.remove();
  map = null;
});

// ── 통계 (취소된 기록 제외) ──
const activeRecords = computed(() => todayRecords.value.filter(r => r.status !== 'voided'));

const checkedInCount = computed(() => {
  const empIds = new Set(activeRecords.value.filter(r => r.check_type === 'check_in').map(r => r.employee_id));
  return empIds.size;
});

const geoCount = computed(() => activeRecords.value.filter(r => r.is_within_geofence).length);
const totalEmployees = computed(() => employees.value.length);

// 오늘(자카르타) 날짜 라벨 — 브라우저가 한국 시간이어도 자카르타 하루를 표시
const todayLabel = computed(() =>
  new Date(`${jakartaDate()}T00:00:00+07:00`).toLocaleDateString('ko-KR', {
    timeZone: 'Asia/Jakarta', month: 'long', day: 'numeric', weekday: 'short',
  })
);

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

function shortId(id: string, n = 12): string {
  return id.length > n ? id.slice(0, n) + '…' : id;
}

// ── 셀피 보기 (private 버킷 → signed URL 60초) ──
const selfieUrl = ref<string | null>(null);
const selfieTitle = ref('');
const selfieLoading = ref(false);

async function openSelfie(rec: AttendanceRecord) {
  if (!rec.selfie_url) return;
  selfieLoading.value = true;
  try {
    selfieUrl.value = await getSelfieSignedUrl(rec.selfie_url);
    selfieTitle.value = `${rec.employee?.name ?? '-'} · ${rec.check_type === 'check_in' ? '출근' : '퇴근'} ${formatJakartaTime(rec.check_time)}`;
  } catch (e: any) {
    alert('셀피를 불러오지 못했습니다: ' + (e.message || '알 수 없는 오류'));
  } finally {
    selfieLoading.value = false;
  }
}

// ── HR 수기 추가 (super_admin) ──
const showManualModal = ref(false);
const manualSaving = ref(false);
const manualForm = ref({ employee_id: '', check_type: 'check_in' as 'check_in' | 'check_out', time: '', reason: '' });

function openManualAdd() {
  manualForm.value = { employee_id: '', check_type: 'check_in', time: toJakartaLocalInput(new Date()), reason: '' };
  showManualModal.value = true;
}

const manualValid = computed(() =>
  !!manualForm.value.employee_id && !!manualForm.value.time && manualForm.value.reason.trim().length > 0
);

async function submitManualAdd() {
  if (!manualValid.value || manualSaving.value) return;
  manualSaving.value = true;
  try {
    await addManualAttendance(
      manualForm.value.employee_id,
      manualForm.value.check_type,
      fromJakartaLocalInput(manualForm.value.time),
      manualForm.value.reason.trim(),
    );
    showManualModal.value = false;
    await loadData();
  } catch (e: any) {
    alert(e.message || '수기 추가에 실패했습니다');
  } finally {
    manualSaving.value = false;
  }
}

// ── 정정 / 취소 (super_admin) — 하나의 사유 모달을 mode 로 나눠 쓴다 ──
const actionModal = ref<{ mode: 'correct' | 'void'; rec: AttendanceRecord } | null>(null);
const actionForm = ref({ time: '', reason: '' });
const actionSaving = ref(false);

function openCorrect(rec: AttendanceRecord) {
  actionForm.value = { time: toJakartaLocalInput(rec.check_time), reason: '' };
  actionModal.value = { mode: 'correct', rec };
}

function openVoid(rec: AttendanceRecord) {
  actionForm.value = { time: '', reason: '' };
  actionModal.value = { mode: 'void', rec };
}

const actionValid = computed(() => {
  if (!actionModal.value) return false;
  if (actionForm.value.reason.trim().length === 0) return false;
  return actionModal.value.mode === 'void' || !!actionForm.value.time;
});

async function submitAction() {
  if (!actionModal.value || !actionValid.value || actionSaving.value) return;
  const { mode, rec } = actionModal.value;
  actionSaving.value = true;
  try {
    if (mode === 'correct') {
      await correctAttendance(rec.id, fromJakartaLocalInput(actionForm.value.time), actionForm.value.reason.trim());
    } else {
      await voidAttendance(rec.id, actionForm.value.reason.trim());
    }
    actionModal.value = null;
    await loadData();
  } catch (e: any) {
    alert(e.message || (mode === 'correct' ? '정정에 실패했습니다' : '취소에 실패했습니다'));
  } finally {
    actionSaving.value = false;
  }
}

// ── 기기 승인 ──
// 승인 대기(is_active=false)를 먼저, 그 안에서는 최근 등록순
const sortedDevices = computed(() =>
  [...devices.value].sort((a, b) =>
    Number(a.is_active) - Number(b.is_active) || (b.registered_at ?? '').localeCompare(a.registered_at ?? '')
  )
);
const pendingDeviceCount = computed(() => devices.value.filter(d => !d.is_active).length);

async function onApproveDevice(d: EmployeeDevice) {
  try {
    await approveDevice(d.id);
    await loadDevices();
  } catch (e: any) {
    alert('승인 실패: ' + (e.message || '알 수 없는 오류'));
  }
}

async function onRevokeDevice(d: EmployeeDevice) {
  if (!confirm(`${d.employee?.name ?? '직원'}의 기기 "${d.device_label ?? shortId(d.device_id)}" 를 폐기하시겠습니까?\n이 기기로는 더 이상 출퇴근을 찍을 수 없습니다.`)) return;
  try {
    await revokeDevice(d.id);
    await loadDevices();
  } catch (e: any) {
    alert('폐기 실패: ' + (e.message || '알 수 없는 오류'));
  }
}

// ── 이탈 알림 ──
const unackedExitCount = computed(() => alerts.value.filter(a => a.alert_type === 'exit' && !a.acknowledged).length);

async function onAcknowledge(a: GeofenceAlert) {
  try {
    await acknowledgeAlert(a.id, adminEmployeeId.value);
    await loadAlerts();
  } catch (e: any) {
    alert('확인 처리 실패: ' + (e.message || '알 수 없는 오류'));
  }
}

// ── 지오펜싱 영역 관리 ──
function openAddZone() {
  editingZoneId.value = null;
  zoneForm.value = { name: '', description: '', latitude: -6.2088, longitude: 106.8456, radius_meters: 100 };
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
        <div class="rounded-xl border border-border bg-card overflow-hidden isolate lg:col-span-2" style="min-height: 320px;">
          <div id="attendance-map" class="w-full h-full" style="min-height: 320px;"></div>
        </div>
      </div>

      <!-- 오늘 출퇴근 기록 -->
      <div class="rounded-xl border border-border bg-card p-4">
        <div class="flex items-center justify-between mb-3">
          <h2 class="font-semibold text-sm">{{ todayLabel }} 출퇴근 기록 <span class="text-xs font-normal text-muted-foreground">(자카르타 기준)</span></h2>
          <Button v-if="isSuperAdmin" size="sm" variant="outline" @click="openManualAdd">
            <Plus :size="14" class="mr-1" /> 수기 추가
          </Button>
        </div>
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
                <th class="py-2 pr-3 font-medium">상태</th>
                <th class="py-2 pr-3 font-medium">지오펜싱</th>
                <th class="py-2 pr-3 font-medium">거리</th>
                <th class="py-2 pr-3 font-medium">기기</th>
                <th class="py-2 pr-3 font-medium">셀피</th>
                <th v-if="isSuperAdmin" class="py-2 font-medium">작업</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="rec in todayRecords" :key="rec.id"
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
                  <div>{{ formatJakartaTime(rec.check_time) }}</div>
                  <div v-if="rec.status === 'corrected' && rec.original_check_time" class="text-xs text-muted-foreground">
                    원래 {{ formatJakartaTime(rec.original_check_time) }}
                  </div>
                </td>
                <td class="py-2.5 pr-3">
                  <span v-if="rec.status === 'normal'" class="text-xs text-muted-foreground">정상</span>
                  <Badge
                    v-else
                    :variant="statusMeta(rec.status).variant"
                    :title="rec.correction_reason ? `${rec.corrector?.name ? rec.corrector.name + ' · ' : ''}${rec.correction_reason}` : undefined"
                  >
                    {{ statusMeta(rec.status).label }}
                  </Badge>
                </td>
                <td class="py-2.5 pr-3">
                  <span v-if="rec.latitude === null || rec.longitude === null" class="text-muted-foreground">-</span>
                  <span v-else-if="rec.is_within_geofence" class="text-green-600 flex items-center gap-1">
                    <CheckCircle2 :size="13" /> {{ rec.geofence_zone?.name ?? '영역 내' }}
                  </span>
                  <span v-else class="text-amber-600 flex items-center gap-1">
                    <AlertTriangle :size="13" /> 영역 밖
                  </span>
                </td>
                <td class="py-2.5 pr-3">{{ rec.distance_meters ? Math.round(rec.distance_meters) + 'm' : '-' }}</td>
                <td class="py-2.5 pr-3 text-muted-foreground max-w-40 truncate" :title="rec.device_id ?? undefined">{{ deviceLabel(rec) }}</td>
                <td class="py-2.5 pr-3">
                  <button
                    v-if="rec.selfie_url"
                    class="inline-flex items-center gap-1 rounded-md border border-border bg-primary-soft px-2 py-0.5 text-xs hover:bg-secondary disabled:opacity-50"
                    :disabled="selfieLoading"
                    @click="openSelfie(rec)"
                  >
                    <Camera :size="12" /> 보기
                  </button>
                  <span v-else class="text-muted-foreground">-</span>
                </td>
                <td v-if="isSuperAdmin" class="py-2.5">
                  <div v-if="rec.status !== 'voided'" class="flex gap-1">
                    <button class="rounded-md border border-border px-2 py-0.5 text-xs hover:bg-accent" @click="openCorrect(rec)">정정</button>
                    <button class="rounded-md border border-border px-2 py-0.5 text-xs text-destructive hover:bg-destructive-soft" @click="openVoid(rec)">취소</button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- 기기 승인 + 이탈 알림 -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <!-- 기기 승인 -->
        <div class="rounded-xl border border-border bg-card p-4">
          <div class="flex items-center justify-between mb-1">
            <h2 class="font-semibold text-sm flex items-center gap-2">
              <Smartphone :size="15" class="text-muted-foreground" /> 기기 승인
              <Badge v-if="pendingDeviceCount" variant="warning">대기 {{ pendingDeviceCount }}</Badge>
            </h2>
            <button class="text-xs text-muted-foreground hover:text-foreground" @click="loadDevices">새로고침</button>
          </div>
          <p class="text-xs text-muted-foreground mb-3">
            직원은 승인된 기기에서만 출퇴근을 찍을 수 있습니다. 활성 기기가 0대가 되면 다음에 등록되는 기기가 자동 승인됩니다.
          </p>
          <p v-if="devicesError" class="text-sm text-destructive py-2">{{ devicesError }}</p>
          <div v-else-if="devices.length === 0" class="text-sm text-muted-foreground py-4 text-center">
            등록된 기기가 없습니다
          </div>
          <div v-else class="space-y-2">
            <div
              v-for="d in sortedDevices" :key="d.id"
              :class="cn('rounded-lg border p-3 flex items-center justify-between gap-3', d.is_active ? 'border-border' : 'border-warning-border bg-warning-soft/40')"
            >
              <div class="min-w-0">
                <div class="flex items-center gap-2 text-sm">
                  <span class="font-medium">{{ d.employee?.name ?? '-' }}</span>
                  <span class="text-muted-foreground text-xs">{{ d.employee?.department ?? '' }}</span>
                  <Badge :variant="d.is_active ? 'success' : 'warning'">{{ d.is_active ? '활성' : '승인 대기' }}</Badge>
                </div>
                <div class="text-xs text-muted-foreground mt-0.5 truncate" :title="d.device_id">
                  {{ d.device_label || '(라벨 없음)' }} · <span class="font-mono">{{ shortId(d.device_id) }}</span>
                </div>
                <div class="text-xs text-muted-foreground">
                  등록 {{ d.registered_at ? formatJakartaDateTime(d.registered_at) : '-' }}
                  <span v-if="d.last_seen_at"> · 최근 {{ formatJakartaDateTime(d.last_seen_at) }}</span>
                </div>
              </div>
              <div v-if="isSuperAdmin" class="shrink-0">
                <Button v-if="!d.is_active" size="sm" @click="onApproveDevice(d)">승인</Button>
                <Button v-else size="sm" variant="outline" class="text-destructive" @click="onRevokeDevice(d)">폐기</Button>
              </div>
            </div>
          </div>
        </div>

        <!-- 이탈 알림 (오늘) -->
        <div class="rounded-xl border border-border bg-card p-4">
          <div class="flex items-center justify-between mb-1">
            <h2 class="font-semibold text-sm flex items-center gap-2">
              <Bell :size="15" class="text-muted-foreground" /> 이탈 알림 (오늘)
              <Badge v-if="unackedExitCount" variant="warning">미확인 {{ unackedExitCount }}</Badge>
            </h2>
            <button class="text-xs text-muted-foreground hover:text-foreground" @click="loadAlerts">새로고침</button>
          </div>
          <p class="text-xs text-muted-foreground mb-3">
            근무 중(출근 후 퇴근 전) 근무지 반경을 벗어나거나 복귀했을 때 기록됩니다. 퇴근 기록을 만들지는 않습니다.
          </p>
          <p v-if="alertsError" class="text-sm text-destructive py-2">{{ alertsError }}</p>
          <div v-else-if="alerts.length === 0" class="text-sm text-muted-foreground py-4 text-center">
            오늘 이탈 알림이 없습니다
          </div>
          <div v-else class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-border text-left text-muted-foreground">
                  <th class="py-2 pr-3 font-medium">시간</th>
                  <th class="py-2 pr-3 font-medium">직원</th>
                  <th class="py-2 pr-3 font-medium">유형</th>
                  <th class="py-2 pr-3 font-medium">근무지</th>
                  <th class="py-2 pr-3 font-medium">거리</th>
                  <th class="py-2 font-medium">확인</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="a in alerts" :key="a.id" class="border-b border-border/50 hover:bg-accent/50">
                  <td class="py-2 pr-3 whitespace-nowrap">{{ formatJakartaTime(a.created_at) }}</td>
                  <td class="py-2 pr-3">
                    <span class="font-medium">{{ a.employee?.name ?? '-' }}</span>
                    <span class="text-muted-foreground text-xs ml-1">{{ a.employee?.department ?? '' }}</span>
                  </td>
                  <td class="py-2 pr-3">
                    <Badge :variant="a.alert_type === 'exit' ? 'warning' : 'success'">{{ a.alert_type === 'exit' ? '이탈' : '복귀' }}</Badge>
                  </td>
                  <td class="py-2 pr-3 text-muted-foreground">{{ a.geofence_zone?.name ?? '-' }}</td>
                  <td class="py-2 pr-3">{{ a.distance_meters != null ? Math.round(a.distance_meters) + 'm' : '-' }}</td>
                  <td class="py-2">
                    <template v-if="a.alert_type === 'exit'">
                      <span v-if="a.acknowledged" class="text-xs text-muted-foreground flex items-center gap-1">
                        <CheckCircle2 :size="12" /> 확인됨
                      </span>
                      <button
                        v-else-if="isSuperAdmin"
                        class="rounded-md border border-border px-2 py-0.5 text-xs hover:bg-accent"
                        @click="onAcknowledge(a)"
                      >확인</button>
                      <span v-else class="text-xs text-amber-600">미확인</span>
                    </template>
                    <span v-else class="text-muted-foreground">-</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
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

    <!-- 수기 추가 모달 (super_admin) -->
    <div v-if="showManualModal" class="fixed inset-0 z-50 flex items-center justify-center bg-black/40" @click.self="showManualModal = false">
      <div class="bg-card rounded-xl border border-border shadow-2xl p-6 w-full max-w-md mx-4">
        <h3 class="font-semibold text-lg mb-1">출퇴근 수기 추가</h3>
        <p class="text-xs text-muted-foreground mb-4">누락된 출근·퇴근을 HR 이 대신 기록합니다. 좌표·셀피 없이 저장되며 정정 사유가 감사 기록으로 남습니다. (시각은 자카르타 기준)</p>
        <div class="form-grid">
          <div class="form-field">
            <label>직원<span class="required">*</span></label>
            <select v-model="manualForm.employee_id">
              <option value="" disabled>직원을 선택하세요</option>
              <option v-for="e in employees" :key="e.id" :value="e.id">{{ e.name }} · {{ e.department }}</option>
            </select>
          </div>
          <div class="form-field">
            <label>유형<span class="required">*</span></label>
            <select v-model="manualForm.check_type">
              <option value="check_in">출근</option>
              <option value="check_out">퇴근</option>
            </select>
          </div>
          <div class="form-field">
            <label>시각 (Asia/Jakarta)<span class="required">*</span></label>
            <input v-model="manualForm.time" type="datetime-local" />
          </div>
          <div class="form-field">
            <label>사유<span class="required">*</span></label>
            <textarea v-model="manualForm.reason" rows="3" placeholder="예: 앱 오류로 퇴근 기록 누락 — 본인 확인 완료"></textarea>
          </div>
        </div>
        <div class="flex justify-end gap-2 mt-5">
          <Button variant="outline" @click="showManualModal = false">취소</Button>
          <Button :disabled="!manualValid || manualSaving" @click="submitManualAdd">{{ manualSaving ? '저장 중…' : '추가' }}</Button>
        </div>
      </div>
    </div>

    <!-- 정정 / 취소 모달 (super_admin) -->
    <div v-if="actionModal" class="fixed inset-0 z-50 flex items-center justify-center bg-black/40" @click.self="actionModal = null">
      <div class="bg-card rounded-xl border border-border shadow-2xl p-6 w-full max-w-md mx-4">
        <h3 class="font-semibold text-lg mb-1">{{ actionModal.mode === 'correct' ? '출퇴근 시각 정정' : '출퇴근 기록 취소' }}</h3>
        <p class="text-xs text-muted-foreground mb-4">
          {{ actionModal.rec.employee?.name ?? '-' }} · {{ actionModal.rec.check_type === 'check_in' ? '출근' : '퇴근' }}
          · 현재 {{ formatJakartaDateTime(actionModal.rec.check_time) }}
          <template v-if="actionModal.mode === 'void'"><br />취소된 기록은 삭제되지 않고 '취소' 상태로 남습니다(감사 추적).</template>
        </p>
        <div class="form-grid">
          <div v-if="actionModal.mode === 'correct'" class="form-field">
            <label>정정 시각 (Asia/Jakarta)<span class="required">*</span></label>
            <input v-model="actionForm.time" type="datetime-local" />
          </div>
          <div class="form-field">
            <label>{{ actionModal.mode === 'correct' ? '정정 사유' : '취소 사유' }}<span class="required">*</span></label>
            <textarea v-model="actionForm.reason" rows="3" placeholder="사유를 입력하세요"></textarea>
          </div>
        </div>
        <div class="flex justify-end gap-2 mt-5">
          <Button variant="outline" @click="actionModal = null">닫기</Button>
          <Button
            :variant="actionModal.mode === 'void' ? 'destructive' : 'default'"
            :disabled="!actionValid || actionSaving"
            @click="submitAction"
          >{{ actionSaving ? '처리 중…' : (actionModal.mode === 'correct' ? '정정' : '기록 취소') }}</Button>
        </div>
      </div>
    </div>

    <!-- 셀피 보기 모달 -->
    <div v-if="selfieUrl" class="fixed inset-0 z-50 flex items-center justify-center bg-black/60" @click.self="selfieUrl = null">
      <div class="bg-card rounded-xl border border-border shadow-2xl p-4 w-full max-w-sm mx-4">
        <div class="flex items-center justify-between mb-3">
          <h3 class="font-semibold text-sm">{{ selfieTitle }}</h3>
          <button class="text-xs text-muted-foreground hover:text-foreground" @click="selfieUrl = null">닫기</button>
        </div>
        <img :src="selfieUrl" alt="출퇴근 셀피" class="w-full rounded-lg border border-border object-contain max-h-[70vh] bg-muted" />
        <p class="text-[11px] text-muted-foreground mt-2">링크는 60초 후 만료됩니다. 셀피는 촬영 후 90일이 지나면 자동 삭제됩니다.</p>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* 라벨이 있는 폼 = 전역 .form-grid/.form-field 규격(CLAUDE.md 입력창 디자인, 2026-08-19).
   이 브랜치의 src/style.css 에는 아직 해당 전역 클래스가 없어 같은 규격을 이 화면에 한정해 정의한다
   (채움 #ECEFF1 · 라벨 12px #546E7A · 값 14px #37474F · focus 흰 배경 + #546E7A 테두리). */
.form-grid { display: grid; gap: 12px; }
.form-field { display: flex; flex-direction: column; gap: 4px; }
.form-field > label { font-size: 12px; color: #546E7A; padding-left: 12px; }
.form-field > label .required { color: var(--destructive); margin-left: 2px; }
.form-field > input,
.form-field > select,
.form-field > textarea {
  width: 100%;
  background: #ECEFF1;
  color: #37474F;
  font-size: 14px;
  border: 1px solid transparent;
  border-radius: 6px;
  padding: 8px 12px;
  outline: none;
  transition: background-color .15s, border-color .15s;
}
.form-field > select { appearance: auto; }
.form-field > textarea { resize: vertical; }
.form-field > input:focus,
.form-field > select:focus,
.form-field > textarea:focus {
  background: #FFFFFF;
  border-color: #546E7A;
}
</style>
