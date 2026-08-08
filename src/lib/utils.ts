import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}

export function previewContent(content: string): string {
  return content.replace(/#{1,3} /g, '').slice(0, 180);
}

// 데이터 로딩 실패 사유를 사용자에게 보여줄 한 줄로 정리한다.
// sb* 헬퍼는 `GET path: 401` 형태로 throw 하므로 대표적인 원인만 우리말로 바꿔준다.
// (TableState / DataState 의 error 프롭에 그대로 넣는 용도)
export function errMsg(e: unknown): string {
  const raw = e instanceof Error ? e.message : String(e);
  if (/Failed to fetch|NetworkError|Load failed/i.test(raw)) {
    return '네트워크에 연결할 수 없습니다. 연결 상태를 확인한 뒤 다시 시도해 주세요.';
  }
  if (/:\s*40[13]\b/.test(raw)) {
    return `접근 권한이 없습니다. 로그아웃 후 다시 로그인해 주세요. (${raw})`;
  }
  if (/:\s*5\d\d\b/.test(raw)) {
    return `서버가 일시적으로 응답하지 않습니다. 잠시 후 다시 시도해 주세요. (${raw})`;
  }
  return raw;
}
