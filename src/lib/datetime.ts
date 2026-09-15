/**
 * 시간대(WIB = Asia/Jakarta, UTC+7) 단일 진실원천.
 *
 * 앱의 모든 "오늘"·"현재 시각"·날짜 경계는 WIB 기준이다. 사업장이 인도네시아이고
 * 서버(RPC·배치·pg_cron)도 전부 `AT TIME ZONE 'Asia/Jakarta'` 로 하루를 자르기 때문에,
 * 관리자 브라우저가 한국(UTC+9)이든 어디든 같은 하루를 봐야 한다.
 *
 * ⚠ `new Date().toISOString().slice(0, 10)` 은 **UTC 날짜**라 WIB 00:00~07:00 사이에
 *   하루 전 날짜가 나온다. 날짜가 필요하면 반드시 이 모듈의 `wibDate()` 를 쓸 것.
 *
 * DB 저장은 timestamptz(UTC)가 정상이며, 변환은 조회·표시 시점에 한다.
 */
export const WIB_TZ = 'Asia/Jakarta';
export const WIB_OFFSET = '+07:00';

/** WIB 기준 'YYYY-MM-DD' (기본값 = 지금) */
export function wibDate(d: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: WIB_TZ, year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(d);
}

/** WIB 기준 오늘에서 n일 전/후의 'YYYY-MM-DD' */
export function wibDateOffset(days: number, from: Date = new Date()): string {
  return wibDate(new Date(from.getTime() + days * 86400000));
}

/** WIB 하루의 [from, to] ISO 경계. PostgREST 쿼리에 넣을 때는 반드시 encodeURIComponent (+ → %2B). */
export function wibDayRange(date: string): { from: string; to: string } {
  return { from: `${date}T00:00:00${WIB_OFFSET}`, to: `${date}T23:59:59.999${WIB_OFFSET}` };
}

/** HH:mm (WIB 벽시계) */
export function formatWibTime(iso: string): string {
  return new Date(iso).toLocaleTimeString('ko-KR', { timeZone: WIB_TZ, hour: '2-digit', minute: '2-digit' });
}

/** YYYY. MM. DD. HH:mm (WIB 벽시계) */
export function formatWibDateTime(iso: string): string {
  return new Date(iso).toLocaleString('ko-KR', {
    timeZone: WIB_TZ, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit',
  });
}

/** MM. DD. HH:mm (WIB 벽시계) — 목록처럼 연도가 불필요한 곳 */
export function formatWibShort(iso: string): string {
  return new Date(iso).toLocaleString('ko-KR', {
    timeZone: WIB_TZ, month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit',
  });
}

/** 'YYYY-MM-DD' → 'M월 D일' 등 날짜만 표기 (WIB 고정 — 브라우저 시간대에 밀리지 않게) */
export function formatWibDateLabel(
  date: string,
  opts: Intl.DateTimeFormatOptions = { month: 'long', day: 'numeric' },
): string {
  return new Date(`${date}T00:00:00${WIB_OFFSET}`).toLocaleDateString('ko-KR', { timeZone: WIB_TZ, ...opts });
}

/** ISO → <input type="datetime-local"> 값('YYYY-MM-DDTHH:mm', WIB 벽시계) */
export function toWibLocalInput(iso: string | Date): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: WIB_TZ, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(new Date(iso));
  const get = (t: string) => parts.find(p => p.type === t)?.value ?? '00';
  return `${get('year')}-${get('month')}-${get('day')}T${get('hour')}:${get('minute')}`;
}

/** datetime-local 값('YYYY-MM-DDTHH:mm')을 WIB 시각으로 해석한 ISO 문자열 */
export function fromWibLocalInput(value: string): string {
  return `${value}:00${WIB_OFFSET}`;
}
