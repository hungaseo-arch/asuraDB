"""
Google OAuth 인증 — 1회 실행으로 token.json 생성
Drive API + Gmail API 공용 토큰
"""
import os
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

from google_auth_oauthlib.flow import InstalledAppFlow

SCOPES = [
    "https://www.googleapis.com/auth/drive.readonly",
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.compose",
    "https://www.googleapis.com/auth/calendar.readonly",
]

CLIENT_CONFIG = {
    "installed": {
        "client_id":                  os.environ["GOOGLE_CLIENT_ID"],
        "client_secret":              os.environ["GOOGLE_CLIENT_SECRET"],
        "redirect_uris":              ["http://localhost:9090/"],
        "auth_uri":                   "https://accounts.google.com/o/oauth2/auth",
        "token_uri":                  "https://oauth2.googleapis.com/token",
    }
}

TOKEN_PATH = os.path.join(os.path.dirname(__file__), "..", "token.json")


def _find_free_port() -> int:
    import socket
    with socket.socket() as s:
        s.bind(("", 0))
        return s.getsockname()[1]


def main():
    port = _find_free_port()

    # redirect_uri를 빈 포트 기반으로 설정
    CLIENT_CONFIG["installed"]["redirect_uris"] = [f"http://localhost:{port}/"]

    flow = InstalledAppFlow.from_client_config(CLIENT_CONFIG, SCOPES)
    print(f"\n포트 {port}에서 로컬 서버 시작 중...")
    creds = flow.run_local_server(port=port, open_browser=True)

    with open(TOKEN_PATH, "w") as f:
        f.write(creds.to_json())

    print(f"\n✅ 인증 완료 — token.json 저장됨")


if __name__ == "__main__":
    main()
