#!/usr/bin/env python3
"""
Launcher server (port 8001) — AsuraDB UI의 'API 오프라인' 버튼 클릭 시
FastAPI 서버(port 8000)를 자동으로 기동하는 경량 HTTP 서버.

Usage: python scripts/launcher.py
"""
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CORS = {
    'Access-Control-Allow-Origin':  '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
}


class Handler(BaseHTTPRequestHandler):
    def _send(self, code: int, body: bytes = b'') -> None:
        self.send_response(code)
        for k, v in CORS.items():
            self.send_header(k, v)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_OPTIONS(self) -> None:
        self._send(204)

    def do_GET(self) -> None:
        self._send(200, b'{"ok":true}') if self.path == '/health' else self._send(404)

    def do_POST(self) -> None:
        if self.path != '/start':
            self._send(404)
            return
        subprocess.Popen(
            ['python3', '-m', 'uvicorn', 'api.search:app',
             '--host', '0.0.0.0', '--port', '8000', '--reload'],
            cwd=ROOT,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        self._send(200, b'{"ok":true}')

    def log_message(self, *_):
        pass


if __name__ == '__main__':
    port = int(os.environ.get('LAUNCHER_PORT', 8001))
    print(f'AsuraDB Launcher listening on :{port}  (FastAPI will start on :8000)')
    HTTPServer(('localhost', port), Handler).serve_forever()
