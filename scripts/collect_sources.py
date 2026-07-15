#!/usr/bin/env python3
"""
문서 소스 1회 수집 오케스트레이터 (LaunchAgent com.asuradb.sources 에서 매일 호출).

각 문서 수집기(notion·gmail·drive·calendar·upnote·band)는 본래 `__main__`에서
collect 1회 후 `schedule` 무한 루프(데몬)로 도는 구조라, 그대로 실행하면 종료되지
않는다. 이 스크립트는 각 수집기의 **1회 수집 함수만** 개별 서브프로세스로 호출해
한 패스만 돌고 종료한다. 한 소스가 실패(예: Google 토큰 만료)해도 나머지는 계속 진행.

수동 실행:  ~/.venvs/asuradb/bin/python scripts/collect_sources.py
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PY = sys.executable
PER_SOURCE_TIMEOUT = 2400  # 초 (수집기당; Notion 전체 재동기화 대비 40분)

# (표시명, 1회 수집 호출 코드)
SOURCES = [
    ("notion",   "from collectors.notion_collector import collect_all; collect_all()"),
    ("gmail",    "from collectors.gmail_collector import collect_all; collect_all()"),
    ("drive",    "from collectors.drive_collector import collect_all; collect_all()"),
    ("calendar", "from collectors.calendar_collector import collect_all; collect_all()"),
    ("upnote",   "from collectors.upnote_collector import collect_all; collect_all()"),
    ("band",     "from collectors.band_collector import collect; collect()"),
]


def main() -> int:
    results: dict[str, str] = {}
    for name, code in SOURCES:
        print(f"\n[collect_sources] ▶ {name} 시작", flush=True)
        try:
            r = subprocess.run([PY, "-c", code], cwd=ROOT, timeout=PER_SOURCE_TIMEOUT)
            results[name] = "OK" if r.returncode == 0 else f"FAIL(rc={r.returncode})"
        except subprocess.TimeoutExpired:
            results[name] = "TIMEOUT"
        except Exception as e:  # noqa: BLE001
            results[name] = f"ERR({e})"
        print(f"[collect_sources] ◀ {name}: {results[name]}", flush=True)

    ok = sum(1 for v in results.values() if v == "OK")
    print(f"\n[collect_sources] 완료: {ok}/{len(SOURCES)} 성공 — "
          + ", ".join(f"{k}={v}" for k, v in results.items()), flush=True)
    # 일부 실패해도 launchd 가 thrash 하지 않도록 전부 실패일 때만 비정상 종료
    return 0 if ok > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
