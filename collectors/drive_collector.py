"""
Google Drive → Supabase 수집기
- Drive API v3로 파일 목록 조회 (내 드라이브 전체)
- Google Docs → Markdown 변환
- PDF → 텍스트 추출 (pdfminer)
- content_hash 비교 → 변경 없으면 skip
- 매일 오전 7시 수집
"""
import hashlib
import io
import logging
import os
import sys
import time
from datetime import datetime, timezone

import schedule
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseDownload
from pdfminer.high_level import extract_text_to_fp
from pdfminer.layout import LAParams
from sentence_transformers import SentenceTransformer
from supabase import create_client, Client as SupabaseClient

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from pipeline.chunker import chunk_markdown

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

SUPABASE_URL        = os.environ["SUPABASE_URL"]
SUPABASE_SERVICE_KEY = os.environ["SUPABASE_SERVICE_KEY"]
EMBEDDING_MODEL     = os.environ.get("EMBEDDING_MODEL", "paraphrase-multilingual-MiniLM-L12-v2")
TOKEN_PATH          = os.path.join(os.path.dirname(__file__), "..", "token.json")

SCOPES = [
    "https://www.googleapis.com/auth/drive.readonly",
]

# 수집 대상 MIME 타입
SUPPORTED_MIME = {
    "application/vnd.google-apps.document",      # Google Docs
    "application/pdf",                            # PDF
    "text/plain",                                 # 텍스트
    "text/markdown",
}

supabase: SupabaseClient  = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
embedder: SentenceTransformer = SentenceTransformer(EMBEDDING_MODEL)


def _get_credentials() -> Credentials:
    if not os.path.exists(TOKEN_PATH):
        raise FileNotFoundError(
            f"token.json 없음: python3 scripts/google_auth.py 를 먼저 실행하세요"
        )
    creds = Credentials.from_authorized_user_file(TOKEN_PATH, SCOPES)
    if creds.expired and creds.refresh_token:
        creds.refresh(Request())
        with open(TOKEN_PATH, "w") as f:
            f.write(creds.to_json())
    return creds


def _list_all_files(service) -> list[dict]:
    """내 드라이브에서 지원 MIME 타입 파일 전체 조회"""
    mime_query = " or ".join(f"mimeType='{m}'" for m in SUPPORTED_MIME)
    query = f"({mime_query}) and trashed=false"
    files, token = [], None
    while True:
        resp = service.files().list(
            q=query,
            fields="nextPageToken, files(id, name, mimeType, modifiedTime, webViewLink, parents)",
            pageSize=100,
            pageToken=token,
        ).execute()
        files.extend(resp.get("files", []))
        token = resp.get("nextPageToken")
        if not token:
            break
    return files


def _docs_to_markdown(service, file_id: str) -> str:
    """Google Docs를 Markdown으로 내보내기"""
    req  = service.files().export_media(fileId=file_id, mimeType="text/plain")
    buf  = io.BytesIO()
    dl   = MediaIoBaseDownload(buf, req)
    done = False
    while not done:
        _, done = dl.next_chunk()
    return buf.getvalue().decode("utf-8", errors="replace")


def _pdf_to_text(service, file_id: str) -> str:
    """PDF 바이너리를 텍스트로 추출"""
    req  = service.files().get_media(fileId=file_id)
    buf  = io.BytesIO()
    dl   = MediaIoBaseDownload(buf, req)
    done = False
    while not done:
        _, done = dl.next_chunk()
    buf.seek(0)
    out = io.StringIO()
    extract_text_to_fp(buf, out, laparams=LAParams())
    return out.getvalue()


def _plain_text(service, file_id: str) -> str:
    req  = service.files().get_media(fileId=file_id)
    buf  = io.BytesIO()
    dl   = MediaIoBaseDownload(buf, req)
    done = False
    while not done:
        _, done = dl.next_chunk()
    return buf.getvalue().decode("utf-8", errors="replace")


def _load_existing_hashes() -> dict[tuple[str, int], str]:
    """drive 소스의 기존 해시를 한 번에 로드 → {(source_id, chunk_index): hash}"""
    hashes: dict[tuple[str, int], str] = {}
    offset = 0
    batch  = 1000
    while True:
        resp = (
            supabase.table("documents")
            .select("source_id,chunk_index,content_hash")
            .eq("source", "drive")
            .range(offset, offset + batch - 1)
            .execute()
        )
        rows = resp.data or []
        for row in rows:
            hashes[(row["source_id"], row["chunk_index"])] = row["content_hash"]
        if len(rows) < batch:
            break
        offset += batch
    log.info(f"기존 해시 {len(hashes)}개 로드")
    return hashes


def _remove_deleted_docs(source: str, current_ids: set[str]) -> int:
    """원본에서 삭제된 문서를 Supabase에서 제거"""
    existing_ids: set[str] = set()
    offset, batch = 0, 1000
    while True:
        resp = (
            supabase.table("documents")
            .select("source_id")
            .eq("source", source)
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
        log.info(f"[{source}] 삭제된 파일 없음")
        return 0

    ids_list = list(to_delete)
    for i in range(0, len(ids_list), 100):
        chunk = ids_list[i:i + 100]
        supabase.table("documents").delete().eq("source", source).in_("source_id", chunk).execute()
    log.info(f"[{source}] 원본 삭제 파일 {len(to_delete)}개 → Supabase에서 제거 완료")
    return len(to_delete)


def collect_all():
    log.info("=== Google Drive 전체 수집 시작 ===")
    creds   = _get_credentials()
    service = build("drive", "v3", credentials=creds)
    files   = _list_all_files(service)
    log.info(f"대상 파일 {len(files)}개")

    current_ids = {f["id"] for f in files}
    _remove_deleted_docs("drive", current_ids)

    existing = _load_existing_hashes()
    inserted = skipped = errors = 0

    for f in files:
        file_id   = f["id"]
        name      = f["name"]
        mime      = f["mimeType"]
        modified  = f.get("modifiedTime", "")
        url       = f.get("webViewLink", "")

        try:
            if mime == "application/vnd.google-apps.document":
                content = _docs_to_markdown(service, file_id)
            elif mime == "application/pdf":
                content = _pdf_to_text(service, file_id)
            else:
                content = _plain_text(service, file_id)
        except Exception as e:
            log.warning(f"  파일 읽기 실패 [{name}]: {e}")
            errors += 1
            continue

        # null 바이트 및 제어 문자 제거 (Postgres TEXT 비호환)
        content = content.replace("\x00", "").strip()
        if not content:
            log.debug(f"  빈 파일 skip: {name}")
            continue

        chunks = chunk_markdown(content)
        for idx, chunk in enumerate(chunks):
            text = chunk["text"]
            h    = hashlib.md5(text.encode()).hexdigest()

            if existing.get((file_id, idx)) == h:
                skipped += 1
                continue

            embedding = embedder.encode(text).tolist()
            for attempt in range(4):
                try:
                    supabase.table("documents").upsert(
                        {
                            "source":       "drive",
                            "source_id":    file_id,
                            "chunk_index":  idx,
                            "chunk_type":   chunk["type"],
                            "title":        name,
                            "content":      text,
                            "content_hash": h,
                            "embedding":    embedding,
                            "metadata":     {"mime": mime, "modified": modified},
                            "source_url":   url,
                            "updated_at":   datetime.now(timezone.utc).isoformat(),
                        },
                        on_conflict="source,source_id,chunk_index",
                    ).execute()
                    inserted += 1
                    break
                except Exception as e:
                    if attempt < 3:
                        wait = 2 ** attempt
                        log.warning(f"  upsert 재시도 {attempt+1}/3 ({wait}s): {e}")
                        time.sleep(wait)
                    else:
                        log.error(f"  upsert 최종 실패 [{name}] chunk {idx}: {e}")
                        errors += 1

        log.info(f"  [{name}] chunks={len(chunks)} inserted={inserted} skipped={skipped}")

    log.info(f"=== Drive 수집 완료 — inserted={inserted} skipped={skipped} errors={errors} ===")
    from collectors.heartbeat import record as _hb; _hb("drive")


if __name__ == "__main__":
    collect_all()

    schedule.every().day.at("07:00").do(collect_all)
    log.info("스케줄러 시작 — 매일 오전 7시 수집")

    while True:
        schedule.run_pending()
        time.sleep(60)
