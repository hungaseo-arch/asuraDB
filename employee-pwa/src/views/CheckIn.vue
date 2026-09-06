<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount, computed } from 'vue';
import { useRouter } from 'vue-router';
import { supabase } from '@/lib/supabase';
import {
  fetchEmployee, checkIn, checkOut, fetchTodayStatus, registerDevice,
  uploadSelfie, reportGeofenceExit, clearEmployeeCache, type Employee,
} from '@/lib/attendance';
import { getDeviceId, getDeviceLabel } from '@/lib/device';
import { formatJakartaTime, JAKARTA_TZ } from '@/lib/date';
import BottomNav from '@/components/BottomNav.vue';

const router = useRouter();
const employee = ref<Employee | null>(null);
const loading = ref(true);
const busy = ref(false);
const busyLabel = ref('');
const currentLat = ref<number | null>(null);
const currentLon = ref<number | null>(null);
const lastCheckIn = ref<string | null>(null);
const lastCheckOut = ref<string | null>(null);
const message = ref('');
const messageType = ref<'success' | 'error' | ''>('');
const isLoggedIn = ref(false);

// 기기 승인 상태 — pending 이면 출퇴근 버튼을 막고 안내한다.
const deviceState = ref<'unknown' | 'active' | 'pending' | 'error'>('unknown');
const deviceError = ref('');

const now = ref(new Date());
let clockTimer: number | undefined;
let geoTimer: number | undefined;

const nowTime = computed(() => now.value.toLocaleTimeString('ko-KR', { timeZone: JAKARTA_TZ, hour: '2-digit', minute: '2-digit' }));
const nowDate = computed(() => now.value.toLocaleDateString('ko-KR', { timeZone: JAKARTA_TZ, month: 'long', day: 'numeric', weekday: 'short' }));

const canCheckIn = computed(() => !lastCheckIn.value && deviceState.value === 'active');
const canCheckOut = computed(() => !!lastCheckIn.value && !lastCheckOut.value && deviceState.value === 'active');
const isCheckedOut = computed(() => !!lastCheckOut.value);
const isWorking = computed(() => !!lastCheckIn.value && !lastCheckOut.value);

function setMessage(text: string, type: 'success' | 'error') {
  message.value = text;
  messageType.value = type;
}

async function init() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) {
    isLoggedIn.value = false;
    loading.value = false;
    return;
  }
  isLoggedIn.value = true;
  try {
    employee.value = await fetchEmployee();
    if (!employee.value) throw new Error('이 계정에 연결된 직원 정보가 없습니다. 관리자에게 문의하세요');
    const status = await fetchTodayStatus();
    lastCheckIn.value = status.lastCheckIn;
    lastCheckOut.value = status.lastCheckOut;
    await ensureDevice();
    startGeofenceWatch();
  } catch (e: any) {
    setMessage(e.message || '정보를 불러오지 못했습니다', 'error');
  }
  loading.value = false;
}

// ── 기기 등록 ──
async function ensureDevice() {
  try {
    const r = await registerDevice(getDeviceId(), getDeviceLabel());
    deviceState.value = r.is_active ? 'active' : 'pending';
    deviceError.value = '';
  } catch (e: any) {
    deviceState.value = 'error';
    deviceError.value = e.message || '기기 등록에 실패했습니다';
  }
}

onMounted(() => {
  init();
  clockTimer = window.setInterval(() => { now.value = new Date(); }, 30_000);
});

onBeforeUnmount(() => {
  if (clockTimer) clearInterval(clockTimer);
  stopGeofenceWatch();
  stopCamera();
});

// ── GPS ──
function getGPS(): Promise<{ lat: number; lon: number }> {
  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) {
      reject(new Error('GPS를 지원하지 않는 기기입니다'));
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => resolve({ lat: pos.coords.latitude, lon: pos.coords.longitude }),
      (err) => reject(new Error(getGPSErrorMessage(err))),
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 60000 }
    );
  });
}

function getGPSErrorMessage(err: GeolocationPositionError): string {
  switch (err.code) {
    case err.PERMISSION_DENIED: return '위치 권한이 거부되었습니다. 설정에서 허용해주세요';
    case err.POSITION_UNAVAILABLE: return '위치 정보를 가져올 수 없습니다';
    case err.TIMEOUT: return '위치 확인 시간이 초과되었습니다';
    default: return '알 수 없는 GPS 오류';
  }
}

// ── 근무 중 지오펜스 이탈 감지 (요건 4) ──
// 출근~퇴근 사이 5분마다 좌표를 서버에 보내 이탈/재진입 전이를 geofence_alerts 에 남긴다.
const GEO_INTERVAL_MS = 5 * 60 * 1000;
const geoNotice = ref('');

function startGeofenceWatch() {
  stopGeofenceWatch();
  if (!isWorking.value) return;
  geoTimer = window.setInterval(pingGeofence, GEO_INTERVAL_MS);
  pingGeofence();
}

function stopGeofenceWatch() {
  if (geoTimer) { clearInterval(geoTimer); geoTimer = undefined; }
}

async function pingGeofence() {
  if (!isWorking.value) { stopGeofenceWatch(); return; }
  try {
    const { lat, lon } = await getGPS();
    const result = await reportGeofenceExit(lat, lon);
    if (result === 'exit') geoNotice.value = '⚠️ 근무 구역을 벗어났습니다 (관리자에게 기록됩니다)';
    else if (result === 'reenter') geoNotice.value = '✅ 근무 구역으로 복귀했습니다';
  } catch { /* 백그라운드 점검 — 실패해도 화면을 방해하지 않는다 */ }
}

// ── 셀피 촬영 ──
const cameraOpen = ref(false);
const cameraError = ref('');
const videoEl = ref<HTMLVideoElement | null>(null);
const pendingAction = ref<'check_in' | 'check_out' | null>(null);
let stream: MediaStream | null = null;

async function openCamera(action: 'check_in' | 'check_out') {
  pendingAction.value = action;
  cameraError.value = '';
  cameraOpen.value = true;
  try {
    stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: 'user', width: { ideal: 640 }, height: { ideal: 640 } },
      audio: false,
    });
    if (videoEl.value) {
      videoEl.value.srcObject = stream;
      await videoEl.value.play();
    }
  } catch (e: any) {
    cameraError.value = e?.name === 'NotAllowedError'
      ? '카메라 권한이 거부되었습니다. 설정에서 허용해주세요'
      : (e.message || '카메라를 열 수 없습니다');
  }
}

function stopCamera() {
  stream?.getTracks().forEach(t => t.stop());
  stream = null;
  if (videoEl.value) videoEl.value.srcObject = null;
}

function closeCamera() {
  stopCamera();
  cameraOpen.value = false;
  pendingAction.value = null;
}

function captureBlob(): Promise<Blob> {
  return new Promise((resolve, reject) => {
    const v = videoEl.value;
    if (!v || !v.videoWidth) { reject(new Error('카메라가 준비되지 않았습니다')); return; }
    // 최대 640px 정사각 — 버킷 상한 2MB(phase2.1) 안에 여유 있게 들어간다.
    const size = Math.min(v.videoWidth, v.videoHeight, 640);
    const canvas = document.createElement('canvas');
    canvas.width = size;
    canvas.height = size;
    const ctx = canvas.getContext('2d');
    if (!ctx) { reject(new Error('이미지를 만들 수 없습니다')); return; }
    const sx = (v.videoWidth - Math.min(v.videoWidth, v.videoHeight)) / 2;
    const sy = (v.videoHeight - Math.min(v.videoWidth, v.videoHeight)) / 2;
    const s = Math.min(v.videoWidth, v.videoHeight);
    ctx.drawImage(v, sx, sy, s, s, 0, 0, size, size);
    canvas.toBlob(
      (blob) => blob ? resolve(blob) : reject(new Error('이미지를 만들 수 없습니다')),
      'image/jpeg',
      0.8
    );
  });
}

// ── 출근/퇴근 ──
async function confirmCapture() {
  const action = pendingAction.value;
  if (!action || !employee.value) return;
  busy.value = true;
  try {
    busyLabel.value = '사진 처리 중...';
    const blob = await captureBlob();
    closeCamera();

    busyLabel.value = 'GPS 확인 중...';
    const { lat, lon } = await getGPS();
    currentLat.value = lat;
    currentLon.value = lon;

    busyLabel.value = '사진 업로드 중...';
    const selfiePath = await uploadSelfie(employee.value.id, action, blob);

    busyLabel.value = '기록 중...';
    const deviceId = getDeviceId();
    const rec = action === 'check_in'
      ? await checkIn(lat, lon, deviceId, selfiePath)
      : await checkOut(lat, lon, deviceId, selfiePath);

    if (action === 'check_in') {
      lastCheckIn.value = rec?.check_time ?? new Date().toISOString();
      setMessage('출근이 기록되었습니다', 'success');
      startGeofenceWatch();
    } else {
      lastCheckOut.value = rec?.check_time ?? new Date().toISOString();
      setMessage('퇴근이 기록되었습니다', 'success');
      stopGeofenceWatch();
      geoNotice.value = '';
    }
  } catch (e: any) {
    setMessage(e.message || '처리에 실패했습니다', 'error');
    // 서버가 기기 미승인으로 거부했을 수 있으니 상태를 다시 확인한다.
    if (/기기/.test(e.message ?? '')) await ensureDevice();
  }
  busy.value = false;
  busyLabel.value = '';
}

async function logout() {
  stopGeofenceWatch();
  clearEmployeeCache();
  await supabase.auth.signOut();
  isLoggedIn.value = false;
  employee.value = null;
  lastCheckIn.value = null;
  lastCheckOut.value = null;
  deviceState.value = 'unknown';
  message.value = '';
}

// ── 로그인 ──
const email = ref('');
const password = ref('');
const authLoading = ref(false);
const authError = ref('');

async function doLogin() {
  authLoading.value = true;
  authError.value = '';
  try {
    const { error } = await supabase.auth.signInWithPassword({ email: email.value, password: password.value });
    if (error) throw error;
    clearEmployeeCache();
    loading.value = true;
    await init();
  } catch (e: any) {
    authError.value = e.message || '로그인 실패';
  }
  authLoading.value = false;
}
</script>

<template>
  <!-- 로그인 화면 -->
  <div v-if="!isLoggedIn && !loading" class="min-h-screen flex items-center justify-center bg-background p-4">
    <div class="w-full max-w-sm bg-card rounded-2xl border border-border p-6">
      <div class="text-center mb-6">
        <div class="w-16 h-16 bg-primary rounded-2xl flex items-center justify-center mx-auto mb-3">
          <span class="text-primary-foreground text-2xl font-bold">🏢</span>
        </div>
        <h1 class="text-xl font-bold">근태 관리</h1>
        <p class="text-sm text-muted-foreground mt-1">로그인 후 출퇴근을 기록하세요</p>
      </div>
      <div class="space-y-3">
        <div class="form-field">
          <label for="email">이메일</label>
          <input id="email" v-model="email" type="email" autocomplete="username" @keyup.enter="doLogin" />
        </div>
        <div class="form-field">
          <label for="password">비밀번호</label>
          <input id="password" v-model="password" type="password" autocomplete="current-password" @keyup.enter="doLogin" />
        </div>
        <div v-if="authError" class="text-destructive text-xs text-center">{{ authError }}</div>
        <button @click="doLogin" :disabled="authLoading" class="btn-primary text-sm">
          {{ authLoading ? '로그인 중...' : '로그인' }}
        </button>
      </div>
    </div>
  </div>

  <!-- 메인 화면 -->
  <div v-else-if="isLoggedIn && !loading" class="min-h-screen bg-background pb-20">
    <div class="bg-card border-b border-border px-4 py-3 flex items-center justify-between">
      <div>
        <h1 class="font-bold text-lg">근태 관리</h1>
        <p class="text-xs text-muted-foreground">{{ employee?.name }} · {{ employee?.department }}</p>
      </div>
      <button @click="logout" class="text-xs text-muted-foreground">로그아웃</button>
    </div>

    <!-- 기기 승인 안내 -->
    <div v-if="deviceState === 'pending'"
      class="mx-4 mt-3 px-4 py-3 rounded-xl text-sm bg-warning-soft border border-warning-border text-warning">
      이 기기는 승인 대기 중입니다. 관리자 승인 후 출퇴근을 기록할 수 있습니다.
      <div class="text-xs mt-1 opacity-80">기기: {{ getDeviceLabel() }}</div>
    </div>
    <div v-else-if="deviceState === 'error'"
      class="mx-4 mt-3 px-4 py-3 rounded-xl text-sm bg-destructive-soft text-destructive">
      {{ deviceError }}
      <button @click="ensureDevice" class="underline ml-1">다시 시도</button>
    </div>

    <!-- 메시지 -->
    <div v-if="message" :class="['mx-4 mt-3 px-4 py-2.5 rounded-xl text-sm font-medium text-center',
      messageType === 'success' ? 'bg-success-soft text-success' : 'bg-destructive-soft text-destructive']">
      {{ message }}
    </div>
    <div v-if="geoNotice" class="mx-4 mt-2 px-4 py-2 rounded-xl text-xs text-center bg-secondary text-muted-foreground">
      {{ geoNotice }}
    </div>

    <!-- 출퇴근 카드 -->
    <div class="p-4">
      <div class="bg-card rounded-2xl border border-border p-6">
        <div class="text-center mb-4">
          <div class="text-4xl font-bold">{{ nowTime }}</div>
          <div class="text-sm text-muted-foreground mt-1">{{ nowDate }} · 자카르타</div>
        </div>

        <div class="grid grid-cols-2 gap-4 mb-5">
          <div class="text-center p-3 rounded-xl bg-success-soft">
            <div class="text-xs text-success font-medium">출근</div>
            <div class="text-lg font-bold text-success">{{ formatJakartaTime(lastCheckIn) }}</div>
          </div>
          <div class="text-center p-3 rounded-xl bg-primary-soft">
            <div class="text-xs text-primary font-medium">퇴근</div>
            <div class="text-lg font-bold text-primary">{{ formatJakartaTime(lastCheckOut) }}</div>
          </div>
        </div>

        <div v-if="currentLat !== null && currentLon !== null" class="text-xs text-muted-foreground text-center mb-3">
          📍 {{ currentLat.toFixed(5) }}, {{ currentLon.toFixed(5) }}
        </div>

        <div class="space-y-2">
          <button v-if="canCheckIn" @click="openCamera('check_in')" :disabled="busy" class="btn-primary">
            {{ busy ? busyLabel : '📷 출근하기' }}
          </button>
          <button v-else-if="canCheckOut" @click="openCamera('check_out')" :disabled="busy" class="btn-primary">
            {{ busy ? busyLabel : '📷 퇴근하기' }}
          </button>
          <div v-if="isCheckedOut" class="text-center py-3 text-muted-foreground font-medium text-sm">
            ✅ 오늘 근무 완료
          </div>
          <div v-else-if="deviceState !== 'active'" class="text-center py-3 text-muted-foreground text-xs">
            기기가 승인되면 버튼이 활성화됩니다
          </div>
          <p class="text-xs text-muted-foreground text-center pt-1">
            출퇴근 시 본인 확인용 셀피를 촬영합니다(90일 후 자동 삭제).
          </p>
        </div>
      </div>
    </div>

    <BottomNav active="checkin" />
  </div>

  <div v-else class="min-h-screen flex items-center justify-center bg-background">
    <div class="text-muted-foreground">로딩 중...</div>
  </div>

  <!-- 셀피 촬영 모달 -->
  <div v-if="cameraOpen" class="fixed inset-0 z-50 bg-black/70 flex items-center justify-center p-4">
    <div class="w-full max-w-sm bg-card rounded-2xl p-4 space-y-3">
      <h2 class="font-semibold text-sm text-center">
        {{ pendingAction === 'check_in' ? '출근' : '퇴근' }} 셀피 촬영
      </h2>
      <div class="aspect-square w-full overflow-hidden rounded-xl bg-secondary flex items-center justify-center">
        <video ref="videoEl" playsinline muted autoplay class="w-full h-full object-cover"></video>
      </div>
      <div v-if="cameraError" class="text-xs text-destructive text-center">{{ cameraError }}</div>
      <div class="flex gap-2">
        <button @click="closeCamera" :disabled="busy" class="btn-soft flex-1">취소</button>
        <button @click="confirmCapture" :disabled="busy || !!cameraError" class="btn-primary flex-1 text-sm py-3">
          {{ busy ? busyLabel : '촬영 후 기록' }}
        </button>
      </div>
    </div>
  </div>
</template>
