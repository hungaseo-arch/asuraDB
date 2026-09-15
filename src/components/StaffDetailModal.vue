<script setup lang="ts">
/**
 * 직원 상세 모달 — 급여 표(StaffPayrollTable.vue)에서 행을 클릭하면 열린다.
 *
 * 기본정보·급여 상세는 읽기 전용이고, 연락처(이메일·전화)만 여기서 수정한다.
 * (staff.email·staff.phone — supabase/migrations/add_staff_contact.sql)
 * NPWP·계좌번호 등 PII 가 함께 노출되므로 super_admin 전용 탭 안에서만 쓴다.
 */
import { ref, watch, onMounted, onBeforeUnmount } from 'vue';
import { X, Loader2, Mail, Phone } from 'lucide-vue-next';
import { sbPatch } from '@/lib/supabase';
import { errMsg } from '@/lib/utils';

interface Payroll {
  nik: string; npwp: string | null; no_rek: string | null;
  kode_ter: string | null; ter_pct: number | null;
  gaji_pokok: number | null; tunj_jabatan: number | null;
  total_tunj_tetap: number | null; total_tunj_tidak_tetap: number | null;
  total_bpjs_perusahaan: number | null; total_gaji_gross: number | null;
  total_potongan: number | null; take_home_pay: number | null;
  periode: string;
}
interface StaffRow {
  nik: string; name: string | null; grade?: string | null; position?: string | null;
  location?: string | null; is_active?: boolean | null;
  email?: string | null; phone?: string | null;
}

const props = defineProps<{ pay: Payroll; staff: StaffRow | null }>();
const emit = defineEmits<{
  (e: 'close'): void;
  (e: 'saved', v: { nik: string; email: string | null; phone: string | null }): void;
}>();

const email = ref('');
const phone = ref('');
const saving = ref(false);
const msg = ref('');

// 같은 모달을 열어둔 채 다른 직원으로 바뀌어도 입력값이 남지 않도록 동기화한다.
watch(() => props.staff, s => {
  email.value = s?.email ?? '';
  phone.value = s?.phone ?? '';
  msg.value = '';
}, { immediate: true });

// Esc 로 닫기
const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') emit('close'); };
onMounted(() => window.addEventListener('keydown', onKey));
onBeforeUnmount(() => window.removeEventListener('keydown', onKey));

const fmt = (n: number | null | undefined) => (n == null ? '—' : Number(n).toLocaleString('en-US'));
const txt = (s: string | null | undefined) => (s && String(s).trim() ? String(s) : '—');

async function save() {
  const e = email.value.trim();
  if (e && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e)) { msg.value = '이메일 형식을 확인하세요.'; return; }
  saving.value = true; msg.value = '';
  const body = { email: e || null, phone: phone.value.trim() || null };
  try {
    await sbPatch(`staff?nik=eq.${encodeURIComponent(props.pay.nik)}`, body);
    emit('saved', { nik: props.pay.nik, ...body });
    msg.value = '저장되었습니다.';
  } catch (err) {
    msg.value = `저장 실패: ${errMsg(err)}`;
  }
  saving.value = false;
}
</script>

<template>
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" @click.self="emit('close')">
    <div class="bg-card border border-border rounded-xl shadow-xl w-full max-w-2xl max-h-[88vh] flex flex-col">
      <!-- 헤더 -->
      <div class="flex items-center justify-between px-5 py-3 border-b border-border">
        <div class="flex items-center gap-2 flex-wrap">
          <h2 class="text-sm font-semibold text-foreground">{{ txt(staff?.name) }}</h2>
          <span class="text-xs text-muted-foreground tabular-nums">NIK {{ pay.nik }}</span>
          <span v-if="staff?.is_active === false"
            class="text-[11px] text-muted-foreground bg-muted/40 border border-border rounded px-1.5 py-0.5">퇴사</span>
        </div>
        <button class="text-muted-foreground hover:text-foreground" title="닫기" @click="emit('close')"><X :size="18" /></button>
      </div>

      <div class="flex-1 overflow-y-auto px-5 py-4 space-y-5">
        <!-- 기본 정보 -->
        <section>
          <h3 class="text-[11px] font-semibold text-muted-foreground mb-2">기본 정보</h3>
          <dl class="grid grid-cols-2 sm:grid-cols-4 gap-x-4 gap-y-3 text-sm">
            <div><dt class="text-[11px] text-muted-foreground">레벨</dt><dd class="text-foreground tabular-nums">{{ txt(staff?.grade) }}</dd></div>
            <div><dt class="text-[11px] text-muted-foreground">직급</dt><dd class="text-foreground">{{ txt(staff?.position) }}</dd></div>
            <div><dt class="text-[11px] text-muted-foreground">근무지</dt><dd class="text-foreground">{{ txt(staff?.location) }}</dd></div>
            <div><dt class="text-[11px] text-muted-foreground">기간</dt><dd class="text-foreground tabular-nums">{{ pay.periode }}</dd></div>
          </dl>
        </section>

        <!-- 연락처 (편집) -->
        <section>
          <h3 class="text-[11px] font-semibold text-muted-foreground mb-2">연락처</h3>
          <div class="form-grid sm:grid-cols-2">
            <div class="form-field">
              <label for="staff-email"><Mail :size="11" class="inline -mt-0.5 mr-1" />이메일</label>
              <input id="staff-email" v-model="email" type="email" inputmode="email" placeholder="name@ascendo.co.id" />
            </div>
            <div class="form-field">
              <label for="staff-phone"><Phone :size="11" class="inline -mt-0.5 mr-1" />전화번호</label>
              <input id="staff-phone" v-model="phone" type="tel" inputmode="tel" placeholder="+62 812-3456-7890" />
            </div>
          </div>
        </section>

        <!-- 급여 상세 -->
        <section>
          <h3 class="text-[11px] font-semibold text-muted-foreground mb-2">급여 상세 ({{ pay.periode }}, IDR)</h3>
          <div class="rounded-lg border border-border overflow-hidden">
            <table class="w-full text-sm">
              <caption class="sr-only">직원 급여 상세</caption>
              <tbody>
                <tr class="border-b border-border/50"><th scope="row" class="text-left font-normal text-muted-foreground px-3 py-2">기본급</th><td class="px-3 py-2 text-right tabular-nums">{{ fmt(pay.gaji_pokok) }}</td>
                    <th scope="row" class="text-left font-normal text-muted-foreground px-3 py-2">직책수당</th><td class="px-3 py-2 text-right tabular-nums">{{ fmt(pay.tunj_jabatan) }}</td></tr>
                <tr class="border-b border-border/50"><th scope="row" class="text-left font-normal text-muted-foreground px-3 py-2">고정수당</th><td class="px-3 py-2 text-right tabular-nums">{{ fmt(pay.total_tunj_tetap) }}</td>
                    <th scope="row" class="text-left font-normal text-muted-foreground px-3 py-2">변동수당</th><td class="px-3 py-2 text-right tabular-nums">{{ fmt(pay.total_tunj_tidak_tetap) }}</td></tr>
                <tr class="border-b border-border/50"><th scope="row" class="text-left font-normal text-muted-foreground px-3 py-2">회사부담 BPJS</th><td class="px-3 py-2 text-right tabular-nums">{{ fmt(pay.total_bpjs_perusahaan) }}</td>
                    <th scope="row" class="text-left font-normal text-muted-foreground px-3 py-2">공제 합계</th><td class="px-3 py-2 text-right tabular-nums">{{ fmt(pay.total_potongan) }}</td></tr>
                <tr class="bg-muted/20"><th scope="row" class="text-left font-semibold px-3 py-2">Gross</th><td class="px-3 py-2 text-right tabular-nums font-semibold text-teal-700">{{ fmt(pay.total_gaji_gross) }}</td>
                    <th scope="row" class="text-left font-semibold px-3 py-2">실수령(THP)</th><td class="px-3 py-2 text-right tabular-nums font-semibold text-teal-700">{{ fmt(pay.take_home_pay) }}</td></tr>
              </tbody>
            </table>
          </div>
          <dl class="grid grid-cols-2 sm:grid-cols-4 gap-x-4 gap-y-3 text-sm mt-3">
            <div><dt class="text-[11px] text-muted-foreground">TER 코드</dt><dd class="text-foreground">{{ txt(pay.kode_ter) }}</dd></div>
            <div><dt class="text-[11px] text-muted-foreground">TER %</dt><dd class="text-foreground tabular-nums">{{ pay.ter_pct == null ? '—' : `${pay.ter_pct}%` }}</dd></div>
            <div><dt class="text-[11px] text-muted-foreground">NPWP</dt><dd class="text-foreground tabular-nums">{{ txt(pay.npwp) }}</dd></div>
            <div><dt class="text-[11px] text-muted-foreground">계좌번호</dt><dd class="text-foreground tabular-nums">{{ txt(pay.no_rek) }}</dd></div>
          </dl>
        </section>
      </div>

      <!-- 푸터 -->
      <div class="flex items-center justify-between gap-3 px-5 py-3 border-t border-border">
        <p class="text-[11px]" :class="msg.includes('실패') || msg.includes('확인') ? 'text-destructive' : 'text-muted-foreground'">{{ msg }}</p>
        <div class="flex items-center gap-2">
          <button class="text-xs px-3 py-2 rounded-lg border border-border bg-card hover:bg-accent transition-colors" @click="emit('close')">닫기</button>
          <button :disabled="saving"
            class="inline-flex items-center gap-1.5 text-xs px-3 py-2 rounded-lg bg-primary text-primary-foreground hover:opacity-90 disabled:opacity-50 transition-opacity"
            @click="save">
            <Loader2 v-if="saving" :size="14" class="animate-spin" /> 연락처 저장
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
