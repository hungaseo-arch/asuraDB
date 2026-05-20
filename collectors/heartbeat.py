"""
각 collector가 성공적으로 완료됐을 때 collector_heartbeat 테이블에 기록
"""
import os
from datetime import datetime, timezone

from dotenv import load_dotenv
from supabase import create_client

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

_supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def record(source: str) -> None:
    _supabase.table("collector_heartbeat").upsert(
        {"source": source, "last_run": datetime.now(timezone.utc).isoformat()},
        on_conflict="source",
    ).execute()
