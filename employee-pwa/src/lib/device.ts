// 기기 식별 — 대리출석 방지 Phase 2 RPC(attendance_register_device 등)가 요구하는 device_id.
// 서버에는 저장하지 않는 임의 클라이언트 UUID로, 이 브라우저(앱)를 재설치/재로그인해도
// localStorage 가 유지되는 한 같은 기기로 인식된다 — 사설 인증서 같은 강한 보증은 아니고,
// "이 브라우저가 매번 같은 값을 보낸다"는 최소한의 바인딩이다.

const DEVICE_ID_KEY = 'asuradb_device_id';

function makeUuid(): string {
  // crypto.randomUUID 는 HTTPS(보안 컨텍스트)에서만 존재 — 로컬 http 개발 환경 폴백.
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  const b = new Uint8Array(16);
  crypto.getRandomValues(b);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = Array.from(b, x => x.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

export function getDeviceId(): string {
  let id: string | null = null;
  try { id = localStorage.getItem(DEVICE_ID_KEY); } catch { /* 사파리 비공개 모드 등 */ }
  if (!id) {
    id = makeUuid();
    try { localStorage.setItem(DEVICE_ID_KEY, id); } catch { /* 저장 실패 시 세션 동안만 유지 */ }
  }
  return id;
}

export function getDeviceLabel(): string {
  const ua = navigator.userAgent;
  // iPadOS 13+ 는 UA 가 Macintosh 로 나오므로 터치 포인트로 구분한다.
  const isIpad = /iPad/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
  if (isIpad) return 'iPad';
  if (/iPhone/.test(ua)) return 'iPhone';
  if (/Android/.test(ua)) return 'Android';
  if (/Macintosh/.test(ua)) return 'Mac';
  if (/Windows/.test(ua)) return 'Windows PC';
  return '기타 기기';
}
