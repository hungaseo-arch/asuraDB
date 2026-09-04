<script setup lang="ts">
import { ref, onMounted, computed } from 'vue';
import { useRouter } from 'vue-router';
import { supabase } from '@/lib/supabase';
import { fetchEmployee, checkIn, checkOut, fetchTodayStatus } from '@/lib/attendance';

const router = useRouter();
const employee = ref<any>(null);
const loading = ref(true);
const gpsLoading = ref(false);
const currentLat = ref<number | null>(null);
const currentLon = ref<number | null>(null);
const gpsError = ref<string | null>(null);
const lastCheckIn = ref<string | null>(null);
const lastCheckOut = ref<string | null>(null);
const message = ref('');
const messageType = ref<'success' | 'error' | ''>('');

const isLoggedIn = ref(false);

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
    const status = await fetchTodayStatus();
    lastCheckIn.value = status.lastCheckIn;
    lastCheckOut.value = status.lastCheckOut;
  } catch (e: any) {
    message.value = '직원 정보를 불러오지 못했습니다';
    messageType.value = 'error';
  }
  loading.value = false;
}

onMounted(init);

const canCheckIn = computed(() => !lastCheckIn.value);
const canCheckOut = computed(() => !!lastCheckIn.value && !lastCheckOut.value);
const isCheckedOut = computed(() => !!lastCheckOut.value);

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

async function doCheckIn() {
  gpsLoading.value = true;
  gpsError.value = null;
  try {
    const { lat, lon } = await getGPS();
    currentLat.value = lat;
    currentLon.value = lon;
    await checkIn(employee.value.id, lat, lon);
    lastCheckIn.value = new Date().toISOString();
    message.value = '출근이 기록되었습니다';
    messageType.value = 'success';
  } catch (e: any) {
    gpsError.value = e.message;
    message.value = e.message;
    messageType.value = 'error';
  }
  gpsLoading.value = false;
}

async function doCheckOut() {
  gpsLoading.value = true;
  gpsError.value = null;
  try {
    const { lat, lon } = await getGPS();
    currentLat.value = lat;
    currentLon.value = lon;
    await checkOut(employee.value.id, lat, lon);
    lastCheckOut.value = new Date().toISOString();
    message.value = '퇴근이 기록되었습니다';
    messageType.value = 'success';
  } catch (e: any) {
    gpsError.value = e.message;
    message.value = e.message;
    messageType.value = 'error';
  }
  gpsLoading.value = false;
}

function formatTime(iso: string | null) {
  if (!iso) return '--:--';
  return new Date(iso).toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit' });
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
    await init();
  } catch (e: any) {
    authError.value = e.message || '로그인 실패';
  }
  authLoading.value = false;
}
</script>

<template>
  <!-- 로그인 화면 -->
  <div v-if="!isLoggedIn && !loading" class="min-h-screen flex items-center justify-center bg-slate-50 p-4">
    <div class="w-full max-w-sm bg-white rounded-2xl shadow-lg p-6">
      <div class="text-center mb-6">
        <div class="w-16 h-16 bg-blue-500 rounded-2xl flex items-center justify-center mx-auto mb-3">
          <span class="text-white text-2xl font-bold">🏢</span>
        </div>
        <h1 class="text-xl font-bold">근태 관리</h1>
        <p class="text-sm text-slate-500 mt-1">로그인 후 출퇴근을 기록하세요</p>
      </div>
      <div class="space-y-3">
        <input v-model="email" type="email" placeholder="이메일"
          class="w-full px-4 py-3 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
        <input v-model="password" type="password" placeholder="비밀번호"
          class="w-full px-4 py-3 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
        <div v-if="authError" class="text-red-500 text-xs text-center">{{ authError }}</div>
        <button @click="doLogin" :disabled="authLoading"
          class="w-full py-3 bg-blue-500 text-white rounded-xl font-semibold text-sm hover:bg-blue-600 disabled:opacity-50 transition-colors">
          {{ authLoading ? '로그인 중...' : '로그인' }}
        </button>
      </div>
    </div>
  </div>

  <!-- 메인 화면 -->
  <div v-else-if="isLoggedIn && !loading" class="min-h-screen bg-slate-50">
    <!-- 헤더 -->
    <div class="bg-white border-b border-slate-200 px-4 py-3 flex items-center justify-between">
      <div>
        <h1 class="font-bold text-lg">근태 관리</h1>
        <p class="text-xs text-slate-500">{{ employee?.name }} · {{ employee?.department }}</p>
      </div>
      <button @click="supabase.auth.signOut(); isLoggedIn = false" class="text-xs text-slate-400">로그아웃</button>
    </div>

    <!-- 메시지 -->
    <div v-if="message" :class="['mx-4 mt-3 px-4 py-2.5 rounded-xl text-sm font-medium text-center',
      messageType === 'success' ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-700']">
      {{ message }}
    </div>

    <!-- 출퇴근 카드 -->
    <div class="p-4">
      <div class="bg-white rounded-2xl shadow-sm border border-slate-200 p-6">
        <div class="text-center mb-4">
          <div class="text-4xl font-bold text-slate-800">{{ new Date().toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit' }) }}</div>
          <div class="text-sm text-slate-500 mt-1">{{ new Date().toLocaleDateString('ko-KR', { month: 'long', day: 'numeric', weekday: 'short' }) }}</div>
        </div>

        <!-- 출퇴근 시간 표시 -->
        <div class="grid grid-cols-2 gap-4 mb-5">
          <div class="text-center p-3 rounded-xl bg-green-50">
            <div class="text-xs text-green-600 font-medium">출근</div>
            <div class="text-lg font-bold text-green-700">{{ formatTime(lastCheckIn) }}</div>
          </div>
          <div class="text-center p-3 rounded-xl bg-blue-50">
            <div class="text-xs text-blue-600 font-medium">퇴근</div>
            <div class="text-lg font-bold text-blue-700">{{ formatTime(lastCheckOut) }}</div>
          </div>
        </div>

        <!-- GPS 상태 -->
        <div v-if="currentLat" class="text-xs text-slate-400 text-center mb-3">
          📍 {{ currentLat.toFixed(5) }}, {{ currentLon.toFixed(5) }}
        </div>
        <div v-if="gpsError" class="text-xs text-red-500 text-center mb-3">{{ gpsError }}</div>

        <!-- 버튼 -->
        <div class="space-y-2">
          <button v-if="canCheckIn" @click="doCheckIn" :disabled="gpsLoading"
            class="w-full py-4 bg-green-500 text-white rounded-xl font-bold text-lg hover:bg-green-600 disabled:opacity-50 transition-colors shadow-sm">
            {{ gpsLoading ? 'GPS 확인 중...' : '출근하기' }}
          </button>
          <button v-if="canCheckOut" @click="doCheckOut" :disabled="gpsLoading"
            class="w-full py-4 bg-blue-500 text-white rounded-xl font-bold text-lg hover:bg-blue-600 disabled:opacity-50 transition-colors shadow-sm">
            {{ gpsLoading ? 'GPS 확인 중...' : '퇴근하기' }}
          </button>
          <div v-if="isCheckedOut" class="text-center py-3 text-slate-400 font-medium text-sm">
            ✅ 오늘 근무 완료
          </div>
        </div>
      </div>
    </div>

    <!-- 하단 메뉴 -->
    <div class="fixed bottom-0 left-0 right-0 bg-white border-t border-slate-200 flex">
      <button @click="router.push('/')" class="flex-1 py-3 flex flex-col items-center gap-0.5 text-blue-500">
        <span class="text-lg">🕐</span>
        <span class="text-xs font-medium">출퇴근</span>
      </button>
      <button @click="router.push('/leave')" class="flex-1 py-3 flex flex-col items-center gap-0.5 text-slate-400">
        <span class="text-lg">📝</span>
        <span class="text-xs font-medium">휴가</span>
      </button>
      <button @click="router.push('/history')" class="flex-1 py-3 flex flex-col items-center gap-0.5 text-slate-400">
        <span class="text-lg">📋</span>
        <span class="text-xs font-medium">기록</span>
      </button>
    </div>
  </div>

  <div v-else class="min-h-screen flex items-center justify-center bg-slate-50">
    <div class="text-slate-400">로딩 중...</div>
  </div>
</template>
