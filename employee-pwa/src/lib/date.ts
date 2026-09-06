// 날짜 유틸 — 서버(attendance_* RPC·pg_cron)는 모두 Asia/Jakarta 기준 "하루"로 판단하므로
// 클라이언트도 브라우저 시간대와 무관하게 자카르타 기준으로 맞춘다.
// (기존 코드는 toISOString() = UTC 라서 자카르타 00:00~07:00 사이 기록이 전날로 묶였다.)

export const JAKARTA_TZ = 'Asia/Jakarta';

const ymdFmt = new Intl.DateTimeFormat('en-CA', {
  timeZone: JAKARTA_TZ, year: 'numeric', month: '2-digit', day: '2-digit',
});

/** 자카르타 기준 YYYY-MM-DD */
export function jakartaDate(d: Date = new Date()): string {
  return ymdFmt.format(d);
}

/** 자카르타 기준 YYYY-MM */
export function jakartaMonth(d: Date = new Date()): string {
  return jakartaDate(d).slice(0, 7);
}

/** 자카르타 기준 하루의 시작·끝(ISO, +07:00 오프셋 포함). PostgREST 쿼리스트링에는 `+` 를 %2B 로 인코딩해 넣을 것. */
export function jakartaDayRange(date: string): { from: string; to: string } {
  return { from: `${date}T00:00:00+07:00`, to: `${date}T23:59:59.999+07:00` };
}

/** 자카르타 기준 한 달 범위(YYYY-MM → from/to ISO) */
export function jakartaMonthRange(month: string): { from: string; to: string } {
  const [y, m] = month.split('-').map(Number);
  const lastDay = new Date(Date.UTC(y, m, 0)).getUTCDate();
  return {
    from: `${month}-01T00:00:00+07:00`,
    to: `${month}-${String(lastDay).padStart(2, '0')}T23:59:59.999+07:00`,
  };
}

export function formatJakartaTime(iso: string | null | undefined): string {
  if (!iso) return '--:--';
  return new Date(iso).toLocaleTimeString('ko-KR', { timeZone: JAKARTA_TZ, hour: '2-digit', minute: '2-digit' });
}

export function formatJakartaDateShort(date: string): string {
  // date 는 YYYY-MM-DD (이미 자카르타 기준). 정오 UTC 로 만들면 어느 시간대에서도 같은 날로 표시된다.
  const d = new Date(`${date}T12:00:00Z`);
  const day = ['일', '월', '화', '수', '목', '금', '토'][d.getUTCDay()];
  return `${d.getUTCMonth() + 1}/${d.getUTCDate()} (${day})`;
}
