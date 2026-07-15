#!/usr/bin/env python3
"""
Launcher server (port 8001) — 프런트엔드가 열려 있는 동안 FastAPI(8000)를
자동으로 기동/유지하고, 탭을 닫아 하트비트가 끊기면 자동으로 종료한다.

동작:
  POST /start      → API(8000) 기동 (이미 떠 있으면 무시) + 하트비트 갱신
  POST /heartbeat  → "아직 열려 있음" 신호 (마지막 수신 시각 갱신)
  POST /stop       → API 즉시 종료
  GET  /health     → 런처 생존 확인
  유휴 감시 스레드 → 마지막 하트비트 후 IDLE_TIMEOUT초 지나면 API 종료

실행(중요): uv 가상환경의 uvicorn을 쓰도록 venv 파이썬으로 띄운다.
  uv run python scripts/launcher.py
"""
import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IDLE_TIMEOUT = float(os.environ.get("API_IDLE_TIMEOUT", "20"))  # 초

# collector 가 사용하는 외부 venv 파이썬 (iCloud Deadlock 회피용 — monthly plist 와 동일)
VENV_PYTHON = os.environ.get(
    "ASURADB_VENV_PYTHON",
    os.path.expanduser("~/.venvs/asuradb/bin/python"),
)
COLLECTOR_SCRIPTS = {
    "daily":   "collectors/indicator_collector.py",  # yfinance: 환율 4종 + 브렌트유 등
    "weekly":  "collectors/weekly_collector.py",     # 주간 원자재
    "monthly": "collectors/monthly_collector.py",    # 정책/거시 4종
}

# 로컬 dev 출처만 허용 (외부 악성 사이트의 교차 출처 제어 차단)
ALLOWED_ORIGIN = re.compile(r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$")

_lock = threading.Lock()
_proc: subprocess.Popen | None = None
_last_seen = 0.0


def _api_alive() -> bool:
    try:
        with urllib.request.urlopen("http://localhost:8000/health", timeout=1) as r:
            return r.status == 200
    except Exception:
        return False


def _start_api() -> None:
    """API 기동 (이미 우리가 띄웠거나 외부에서 떠 있으면 무시)."""
    global _proc, _last_seen
    _last_seen = time.time()
    if _proc is not None and _proc.poll() is None:
        return
    if _api_alive():
        return
    _proc = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "api.search:app",
         "--host", "127.0.0.1", "--port", "8000"],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def _stop_api() -> None:
    global _proc
    if _proc is not None and _proc.poll() is None:
        _proc.terminate()
        try:
            _proc.wait(timeout=5)
        except Exception:
            _proc.kill()
    _proc = None


def _reaper() -> None:
    """유휴 감시: 하트비트가 IDLE_TIMEOUT초 이상 끊기면 API 종료."""
    while True:
        time.sleep(5)
        with _lock:
            running = _proc is not None and _proc.poll() is None
            if running and (time.time() - _last_seen) > IDLE_TIMEOUT:
                _stop_api()


# ── collector 실행 ─────────────────────────────────────────────
# Monitor 페이지의 새로고침 버튼이 POST /collect 로 호출 → daily/weekly/monthly
# collector 를 순차 실행하고 결과 요약을 반환. 외부 venv (~/.venvs/asuradb) 의
# 파이썬을 직접 사용해 iCloud Drive Desktop 동기화로 인한 deadlock 회피.

_COLLECTOR_TIMEOUT = 120  # 초 — yfinance/네트워크 호출 여유


def _run_collector(kind: str) -> dict:
    script = COLLECTOR_SCRIPTS[kind]
    args = [VENV_PYTHON, script]
    if kind == "monthly":
        args.append("--force")  # 가드 우회 (사용자가 명시적 새로고침 요청한 경우)
    try:
        proc = subprocess.run(
            args, cwd=ROOT,
            capture_output=True, text=True,
            timeout=_COLLECTOR_TIMEOUT,
        )
        return {
            "kind":      kind,
            "ok":        proc.returncode == 0,
            "exit_code": proc.returncode,
            "tail":      (proc.stdout or "").splitlines()[-1:],
            "err_tail":  (proc.stderr or "").splitlines()[-3:],
        }
    except subprocess.TimeoutExpired:
        return {"kind": kind, "ok": False, "exit_code": -1, "error": "timeout"}
    except FileNotFoundError as e:
        return {"kind": kind, "ok": False, "exit_code": -1, "error": f"venv python 없음: {e}"}
    except Exception as e:
        return {"kind": kind, "ok": False, "exit_code": -1, "error": str(e)}


class Handler(BaseHTTPRequestHandler):
    def _origin_ok(self) -> bool:
        # Origin 없음(curl 등 비브라우저) = 허용. 있으면 로컬 출처만 허용.
        origin = self.headers.get("Origin")
        return origin is None or bool(ALLOWED_ORIGIN.match(origin))

    def _send(self, code: int, body: bytes = b"") -> None:
        self.send_response(code)
        origin = self.headers.get("Origin")
        if origin and ALLOWED_ORIGIN.match(origin):
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_OPTIONS(self) -> None:
        self._send(204 if self._origin_ok() else 403)

    def do_GET(self) -> None:
        self._send(200, b'{"ok":true}') if self.path == "/health" else self._send(404)

    def do_POST(self) -> None:
        global _last_seen
        # 외부 출처에서의 교차 출처 제어(CSRF) 차단
        if not self._origin_ok():
            self._send(403, b'{"error":"forbidden origin"}')
            return
        if self.path == "/start":
            with _lock:
                _start_api()
            self._send(200, b'{"ok":true}')
        elif self.path == "/heartbeat":
            with _lock:
                _last_seen = time.time()
            self._send(200, b'{"ok":true}')
        elif self.path == "/stop":
            with _lock:
                _stop_api()
            self._send(200, b'{"ok":true}')
        elif self.path.startswith("/collect"):
            # /collect          → daily + weekly + monthly 순차
            # /collect/daily    → daily 만
            # /collect/weekly   → weekly 만
            # /collect/monthly  → monthly 만
            tail = self.path[len("/collect"):].lstrip("/")
            kinds = [tail] if tail in COLLECTOR_SCRIPTS else list(COLLECTOR_SCRIPTS.keys())
            results = [_run_collector(k) for k in kinds]
            body = json.dumps({
                "ok":      all(r["ok"] for r in results),
                "results": results,
            }).encode()
            self._send(200, body)
        else:
            self._send(404)

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    port = int(os.environ.get("LAUNCHER_PORT", 8001))
    threading.Thread(target=_reaper, daemon=True).start()
    print(f"AsuraDB Launcher listening on :{port}  "
          f"(FastAPI on :8000, idle-stop after {IDLE_TIMEOUT:.0f}s)")
    HTTPServer(("localhost", port), Handler).serve_forever()
