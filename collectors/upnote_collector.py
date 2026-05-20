"""
UpNote → Supabase 수집기 (SQLite 직접 읽기, 수동 내보내기 불필요)

UpNote 로컬 DB: ~/Library/Containers/com.getupnote.desktop/...
  - notes 테이블: id, title, text, tagLinks, updatedAt, trashed, deleted
  - notebooks 테이블: id, title, deleted
  - organizers 테이블: noteId, notebookId (노트-노트북 연결)
"""
import hashlib
import json
import logging
import os
import shutil
import sqlite3
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import schedule
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

from sentence_transformers import SentenceTransformer
from supabase import create_client, Client as SupabaseClient

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from pipeline.chunker import chunk_markdown

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

SUPABASE_URL         = os.environ["SUPABASE_URL"]
SUPABASE_SERVICE_KEY = os.environ["SUPABASE_SERVICE_KEY"]
EMBEDDING_MODEL      = os.environ.get("EMBEDDING_MODEL", "paraphrase-multilingual-MiniLM-L12-v2")

UPNOTE_DB = Path(
    os.environ.get(
        "UPNOTE_DB_PATH",
        "~/Library/Containers/com.getupnote.desktop/Data/Library/Application Support/UpNote/upnote.sqlite3",
    )
).expanduser()

# SQLite WAL 모드 파일이 열려 있어도 충돌 방지를 위해 임시 복사본 사용
UPNOTE_DB_COPY = Path("/tmp/upnote_collector_snapshot.sqlite3")

supabase: SupabaseClient     = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
embedder: SentenceTransformer = SentenceTransformer(EMBEDDING_MODEL)


def _snapshot_db() -> sqlite3.Connection:
    """UpNote가 실행 중이어도 안전하게 읽기 위해 DB 스냅샷 복사"""
    if not UPNOTE_DB.exists():
        raise FileNotFoundError(f"UpNote DB를 찾을 수 없습니다: {UPNOTE_DB}")
    shutil.copy2(UPNOTE_DB, UPNOTE_DB_COPY)
    return sqlite3.connect(str(UPNOTE_DB_COPY))


def _load_notebooks(conn: sqlite3.Connection) -> dict[str, str]:
    """id → title 매핑"""
    cur = conn.execute("SELECT id, title FROM notebooks WHERE deleted=0")
    return {row[0]: row[1] or "" for row in cur.fetchall()}


def _load_notes(conn: sqlite3.Connection) -> list[dict]:
    """삭제/휴지통 제외한 노트 전량 로드"""
    cur = conn.execute(
        """
        SELECT n.id, n.title, n.text, n.tagLinks, n.updatedAt,
               o.notebookId
        FROM notes n
        LEFT JOIN organizers o ON o.noteId = n.id AND o.deleted = 0
        WHERE n.deleted = 0 AND n.trashed = 0
        """
    )
    rows = cur.fetchall()
    notes: dict[str, dict] = {}
    for note_id, title, text, tag_links, updated_at, notebook_id in rows:
        if note_id in notes:
            # 같은 노트가 여러 노트북에 속할 경우 첫 번째만 사용
            continue
        try:
            tags = json.loads(tag_links or "[]")
        except Exception:
            tags = []
        notes[note_id] = {
            "id":          note_id,
            "title":       title or "",
            "text":        text or "",
            "tags":        tags,
            "updated_at":  updated_at,
            "notebook_id": notebook_id or "",
        }
    return list(notes.values())


def _load_existing_hashes() -> dict[tuple[str, int], str]:
    hashes: dict[tuple[str, int], str] = {}
    offset, batch = 0, 1000
    while True:
        resp = (
            supabase.table("documents")
            .select("source_id,chunk_index,content_hash")
            .eq("source", "upnote")
            .range(offset, offset + batch - 1)
            .execute()
        )
        rows = resp.data or []
        for row in rows:
            hashes[(row["source_id"], row["chunk_index"])] = row["content_hash"]
        if len(rows) < batch:
            break
        offset += batch
    log.info(f"기존 UpNote 해시 {len(hashes)}개 로드")
    return hashes


def _remove_deleted_docs(current_ids: set[str]) -> int:
    existing_ids: set[str] = set()
    offset, batch = 0, 1000
    while True:
        resp = (
            supabase.table("documents")
            .select("source_id")
            .eq("source", "upnote")
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
        log.info("[upnote] 삭제된 노트 없음")
        return 0

    ids_list = list(to_delete)
    for i in range(0, len(ids_list), 100):
        chunk = ids_list[i:i + 100]
        supabase.table("documents").delete().eq("source", "upnote").in_("source_id", chunk).execute()
    log.info(f"[upnote] 삭제된 노트 {len(to_delete)}개 → Supabase에서 제거")
    return len(to_delete)


def collect_all():
    log.info("=== UpNote 전체 수집 시작 ===")

    try:
        conn = _snapshot_db()
    except FileNotFoundError as e:
        log.error(str(e))
        return

    notebooks = _load_notebooks(conn)
    notes     = _load_notes(conn)
    conn.close()

    log.info(f"노트 {len(notes)}개, 노트북 {len(notebooks)}개")

    current_ids = {n["id"] for n in notes}
    _remove_deleted_docs(current_ids)

    existing  = _load_existing_hashes()
    inserted = skipped = errors = 0

    for note in notes:
        note_id    = note["id"]
        title      = note["title"]
        text       = note["text"].replace("\x00", "").strip()
        tags       = note["tags"]
        updated_ms = note["updated_at"] or 0
        nb_title   = notebooks.get(note["notebook_id"], "")

        updated_iso = datetime.fromtimestamp(
            updated_ms / 1000, tz=timezone.utc
        ).isoformat() if updated_ms else None

        if not text:
            log.debug(f"  빈 노트 skip: {title}")
            continue

        meta = {
            "notebook":   nb_title,
            "tags":       tags,
            "updated_at": updated_iso,
            "note_id":    note_id,
        }

        chunks = chunk_markdown(text)
        for idx, chunk in enumerate(chunks):
            chunk_text = chunk["text"]
            h          = hashlib.md5(chunk_text.encode()).hexdigest()

            if existing.get((note_id, idx)) == h:
                skipped += 1
                continue

            embedding = embedder.encode(chunk_text).tolist()
            for attempt in range(4):
                try:
                    supabase.table("documents").upsert(
                        {
                            "source":       "upnote",
                            "source_id":    note_id,
                            "chunk_index":  idx,
                            "chunk_type":   chunk["type"],
                            "title":        title,
                            "content":      chunk_text,
                            "content_hash": h,
                            "embedding":    embedding,
                            "metadata":     meta,
                            "source_url":   f"upnote://x-callback-url/openNote?noteId={note_id}",
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

    log.info(f"=== UpNote 수집 완료 — inserted={inserted} skipped={skipped} errors={errors} ===")
    from collectors.heartbeat import record as _hb; _hb("upnote")


if __name__ == "__main__":
    collect_all()

    schedule.every().day.at("08:00").do(collect_all)
    log.info("스케줄러 시작 — 매일 오전 7시 수집")

    while True:
        schedule.run_pending()
        time.sleep(60)
