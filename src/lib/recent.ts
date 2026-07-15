// 최근 방문 페이지 기록 (localStorage). Command Palette에서 빠른 재방문용.
export interface RecentEntry { path: string; label: string }

const KEY = 'asura_recent_pages';
const MAX = 6;

export function getRecent(): RecentEntry[] {
  try {
    const raw = localStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as RecentEntry[]) : [];
  } catch {
    return [];
  }
}

export function pushRecent(path: string, label: string): void {
  if (!path || !label) return;
  try {
    const list = getRecent().filter(e => e.path !== path);
    list.unshift({ path, label });
    localStorage.setItem(KEY, JSON.stringify(list.slice(0, MAX)));
  } catch {
    /* 저장 실패 무시 */
  }
}
