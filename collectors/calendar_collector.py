"""
Google Calendar → Supabase 수집기
- 수집 범위: 과거 2년 ~ 미래 3개월
- 이벤트별 저장: 제목 / 날짜·시간 / 설명 / 참석자 / 장소
- content_hash 변경 감지 → skip
- 삭제된 이벤트 → Supabase 제거
- 매일 오전 7시 수집
"""
import hashlib
import logging
import os
import sys
import time
from datetime import datetime, timezone, timedelta

import schedule
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from sentence_transformers import SentenceTransformer
from supabase import create_client, Client as SupabaseClient

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from pipeline.chunker import chunk_markdown

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

SUPABASE_URL         = os.environ["SUPABASE_URL"]
SUPABASE_SERVICE_KEY = os.environ["SUPABASE_SERVICE_KEY"]
EMBEDDING_MODEL      = os.environ.get("EMBEDDING_MODEL", "paraphrase-multilingual-MiniLM-L12-v2")
TOKEN_PATH           = os.path.join(os.path.dirname(__file__), "..", "token.json")

# token.json 은 gmail/drive/calendar 수집기가 공유한다. 자기 스코프 하나만 지정해
# refresh 하면 그 스코프로 좁혀진 access token 이 token.json 에 저장되어, 뒤이어
# 도는 다른 수집기가 (아직 유효한 좁은 토큰을 그대로 쓰다) 403 으로 죽는다.
# → 반드시 scripts/google_auth.py 와 동일한 전체 목록으로 refresh 할 것.
GOOGLE_SCOPES = [
    "https://www.googleapis.com/auth/drive.readonly",
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.compose",
    "https://www.googleapis.com/auth/calendar.readonly",
]

PAST_DAYS    = 365 * 10  # 과거 10년
FUTURE_DAYS  = 365 * 2   # 미래 2년

supabase: SupabaseClient     = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
embedder: SentenceTransformer = SentenceTransformer(EMBEDDING_MODEL)


# ── 인증 ──────────────────────────────────────────────────────────────────

def _get_credentials() -> Credentials:
    if not os.path.exists(TOKEN_PATH):
        raise FileNotFoundError("token.json 없음: python3 scripts/google_auth.py 를 먼저 실행하세요")
    creds = Credentials.from_authorized_user_file(TOKEN_PATH, GOOGLE_SCOPES)
    if creds.expired and creds.refresh_token:
        creds.refresh(Request())
        with open(TOKEN_PATH, "w") as f:
            f.write(creds.to_json())
    return creds


# ── 캘린더 이벤트 조회 ──────────────────────────────────────────────────────

def _list_all_calendars(service) -> list[dict]:
    """접근 가능한 캘린더 목록"""
    resp = service.calendarList().list().execute()
    return resp.get("items", [])


def _list_events(service, calendar_id: str, time_min: str, time_max: str) -> list[dict]:
    """단일 캘린더에서 이벤트 전체 조회 (페이징)"""
    events = []
    page_token = None
    while True:
        resp = service.events().list(
            calendarId=calendar_id,
            timeMin=time_min,
            timeMax=time_max,
            singleEvents=True,       # 반복 이벤트 각각 전개
            orderBy="startTime",
            maxResults=250,
            pageToken=page_token,
        ).execute()
        events.extend(resp.get("items", []))
        page_token = resp.get("nextPageToken")
        if not page_token:
            break
    return events


# ── 이벤트 → Markdown ─────────────────────────────────────────────────────

def _attendees_text(attendees: list[dict]) -> str:
    names = []
    for a in attendees:
        display = a.get("displayName") or a.get("email", "")
        if display:
            names.append(display)
    return ", ".join(names)


def _parse_datetime(dt_obj: dict) -> tuple[str, str]:
    """
    {'dateTime': '2024-03-15T10:00:00+09:00'} 또는 {'date': '2024-03-15'}
    → (iso_str, display_str)
    """
    if "dateTime" in dt_obj:
        iso = dt_obj["dateTime"]
        try:
            dt = datetime.fromisoformat(iso)
            display = dt.strftime("%Y-%m-%d %H:%M")
        except ValueError:
            display = iso
        return iso, display
    date_str = dt_obj.get("date", "")
    return date_str, date_str


def _event_to_markdown(event: dict, calendar_name: str) -> tuple[str, dict]:
    """
    이벤트 1개를 Markdown 문서로 변환.
    저장 형식:
        # 제목
        **캘린더:** ...
        **날짜:** ...
        **장소:** ...
        **참석자:** ...

        ## 설명
        ...
    """
    title       = event.get("summary", "(제목 없음)")
    description = (event.get("description") or "").strip()
    location    = (event.get("location") or "").strip()
    attendees   = event.get("attendees", [])
    organizer   = event.get("organizer", {})
    status      = event.get("status", "confirmed")    # confirmed / cancelled / tentative
    event_id    = event.get("id", "")
    html_link   = event.get("htmlLink", "")

    start_iso, start_display = _parse_datetime(event.get("start", {}))
    end_iso,   end_display   = _parse_datetime(event.get("end", {}))

    date_range = (
        f"{start_display} ~ {end_display}"
        if start_display != end_display
        else start_display
    )

    lines = [f"# {title}\n"]
    lines.append(f"**캘린더:** {calendar_name}")
    lines.append(f"**날짜:** {date_range}")
    if location:
        lines.append(f"**장소:** {location}")

    organizer_name = organizer.get("displayName") or organizer.get("email", "")
    if organizer_name:
        lines.append(f"**주최자:** {organizer_name}")

    att_text = _attendees_text(attendees)
    if att_text:
        lines.append(f"**참석자:** {att_text}")

    if description:
        lines.append("\n## 설명\n")
        lines.append(description)

    meta = {
        "calendar":    calendar_name,
        "start":       start_iso,
        "end":         end_iso,
        "date":        start_iso[:10],
        "location":    location,
        "organizer":   organizer_name,
        "attendees":   [a.get("email", "") for a in attendees],
        "status":      status,
        "event_id":    event_id,
    }

    return "\n".join(lines).strip(), meta


# ── Supabase 헬퍼 ──────────────────────────────────────────────────────────

def _load_existing_hashes() -> dict[tuple[str, int], str]:
    hashes: dict[tuple[str, int], str] = {}
    offset, batch = 0, 1000
    while True:
        resp = (
            supabase.table("documents")
            .select("source_id,chunk_index,content_hash")
            .eq("source", "calendar")
            .range(offset, offset + batch - 1)
            .execute()
        )
        rows = resp.data or []
        for row in rows:
            hashes[(row["source_id"], row["chunk_index"])] = row["content_hash"]
        if len(rows) < batch:
            break
        offset += batch
    log.info(f"기존 캘린더 해시 {len(hashes)}개 로드")
    return hashes


def _remove_deleted_events(current_ids: set[str]) -> int:
    """삭제·기간 외 이벤트를 Supabase에서 제거"""
    existing_ids: set[str] = set()
    offset, batch = 0, 1000
    while True:
        resp = (
            supabase.table("documents")
            .select("source_id")
            .eq("source", "calendar")
            .range(offset, offset + batch - 1)
            .execute()
        )
        rows = resp.data or []
        for row in rows:
            existing_ids.add(row["source_id"])
        if len(rows) < batch:
            break
        offset += batch

    to_delete = existing_ids - current_ids
    if not to_delete:
        log.info("[calendar] 삭제된 이벤트 없음")
        return 0

    ids_list = list(to_delete)
    for i in range(0, len(ids_list), 100):
        chunk = ids_list[i:i + 100]
        supabase.table("documents").delete().eq("source", "calendar").in_("source_id", chunk).execute()
    log.info(f"[calendar] 삭제된 이벤트 {len(to_delete)}개 → Supabase에서 제거 완료")
    return len(to_delete)


# ── 수집 메인 ──────────────────────────────────────────────────────────────

def collect_all():
    log.info("=== Google Calendar 전체 수집 시작 ===")
    creds   = _get_credentials()
    service = build("calendar", "v3", credentials=creds)

    now      = datetime.now(timezone.utc)
    time_min = (now - timedelta(days=PAST_DAYS)).isoformat()
    time_max = (now + timedelta(days=FUTURE_DAYS)).isoformat()

    calendars = _list_all_calendars(service)
    log.info(f"접근 가능한 캘린더 {len(calendars)}개")

    # 전체 이벤트 수집
    all_events: list[tuple[dict, str]] = []   # (event, calendar_name)
    for cal in calendars:
        cal_id   = cal["id"]
        cal_name = cal.get("summary", cal_id)
        try:
            events = _list_events(service, cal_id, time_min, time_max)
            for ev in events:
                all_events.append((ev, cal_name))
            log.info(f"  [{cal_name}] {len(events)}개 이벤트")
        except Exception as e:
            log.warning(f"  [{cal_name}] 이벤트 조회 실패: {e}")

    log.info(f"총 이벤트 {len(all_events)}개")

    # 삭제 감지
    current_ids = {ev["id"] for ev, _ in all_events if ev.get("id")}
    _remove_deleted_events(current_ids)

    existing = _load_existing_hashes()
    inserted = skipped = errors = 0

    for event, cal_name in all_events:
        event_id = event.get("id", "")
        if not event_id:
            continue

        # 취소된 이벤트는 건너뜀
        if event.get("status") == "cancelled":
            continue

        try:
            content, meta = _event_to_markdown(event, cal_name)
        except Exception as e:
            log.warning(f"  이벤트 변환 실패 [{event.get('summary','?')}]: {e}")
            errors += 1
            continue

        content = content.replace("\x00", "").strip()
        if not content:
            continue

        title  = event.get("summary", "(제목 없음)")
        chunks = chunk_markdown(content)

        for idx, chunk in enumerate(chunks):
            text = chunk["text"]
            h    = hashlib.md5(text.encode()).hexdigest()

            if existing.get((event_id, idx)) == h:
                skipped += 1
                continue

            embedding = embedder.encode(text).tolist()
            for attempt in range(4):
                try:
                    supabase.table("documents").upsert(
                        {
                            "source":       "calendar",
                            "source_id":    event_id,
                            "chunk_index":  idx,
                            "chunk_type":   chunk["type"],
                            "title":        title,
                            "content":      text,
                            "content_hash": h,
                            "embedding":    embedding,
                            "metadata":     meta,
                            "source_url":   event.get("htmlLink", ""),
                            "updated_at":   datetime.now(timezone.utc).isoformat(),
                        },
                        on_conflict="source,source_id,chunk_index",
                    ).execute()
                    inserted += 1
                    break
                except Exception as e:
                    if attempt < 3:
                        time.sleep(2 ** attempt)
                    else:
                        log.error(f"  upsert 실패 [{title}] chunk {idx}: {e}")
                        errors += 1

    log.info(f"=== Calendar 수집 완료 — inserted={inserted} skipped={skipped} errors={errors} ===")
    from collectors.heartbeat import record as _hb; _hb("calendar")


if __name__ == "__main__":
    collect_all()

    schedule.every().day.at("07:00").do(collect_all)
    log.info("스케줄러 시작 — 매일 오전 7시 수집")

    while True:
        schedule.run_pending()
        time.sleep(60)
