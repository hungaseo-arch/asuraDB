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
import re
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
from sentence_transformers import SentenceTransformer
from supabase import create_client, Client as SupabaseClient

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from pipeline.chunker import chunk_markdown
from collectors import pdf_extract

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

SUPABASE_URL        = os.environ["SUPABASE_URL"]
SUPABASE_SERVICE_KEY = os.environ["SUPABASE_SERVICE_KEY"]
EMBEDDING_MODEL     = os.environ.get("EMBEDDING_MODEL", "paraphrase-multilingual-MiniLM-L12-v2")
TOKEN_PATH          = os.path.join(os.path.dirname(__file__), "..", "token.json")

# PDF 추출은 pdf_extract.extract_isolated 로 격리 실행하고 이 시간(초)을 넘으면 건너뛴다.
# 일부 PDF 가 pdfminer 레이아웃 분석에서 O(n^2) 로 폭주하는 것을 차단(배경: pdf_extract.py).
PDF_TIMEOUT = int(os.environ.get("DRIVE_PDF_TIMEOUT", "90"))

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

# 수집 대상 MIME 타입
SUPPORTED_MIME = {
    "application/vnd.google-apps.document",      # Google Docs
    "application/pdf",                            # PDF
    "text/plain",                                 # 텍스트
    "text/markdown",
}

# ── 민감정보(PII) 제외 필터 ────────────────────────────────────────────────
# 개인 세무·신분 문서는 RAG 코퍼스에 저장하지 않는다(주민번호·여권·계좌 노출 방지).
# (1) 파일명 패턴 — 다운로드 전 사전 차단
SENSITIVE_NAME_PATTERNS = re.compile(
    r"주민|여권|passport|소득금액증명|원천징수|근로소득|소득세|재외국민|"
    r"등본|초본|가족관계|통장|계좌|급여명세|payroll|SPT|1770|1721|NPWP|KTP",
    re.IGNORECASE,
)
# (2) 본문 패턴 — 추출 텍스트에서 실제 PII가 감지되면 파일 전체를 건너뛰는 안전망
PII_CONTENT_PATTERNS = {
    "주민등록번호": re.compile(r"\b\d{6}[-\s]?[1-4]\d{6}\b"),
    "여권번호":     re.compile(r"\b[MSROD]\d{8}\b"),
}


def _is_sensitive_name(name: str) -> bool:
    return bool(SENSITIVE_NAME_PATTERNS.search(name or ""))


def _detect_pii(content: str) -> list[str]:
    """본문에서 감지된 PII 종류 목록(없으면 빈 리스트)"""
    return [label for label, pat in PII_CONTENT_PATTERNS.items() if pat.search(content)]

supabase: SupabaseClient  = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
embedder: SentenceTransformer = SentenceTransformer(EMBEDDING_MODEL)


def _get_credentials() -> Credentials:
    if not os.path.exists(TOKEN_PATH):
        raise FileNotFoundError(
            f"token.json 없음: python3 scripts/google_auth.py 를 먼저 실행하세요"
        )
    creds = Credentials.from_authorized_user_file(TOKEN_PATH, GOOGLE_SCOPES)
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
    """PDF 바이너리를 텍스트로 추출.

    pdfminer 추출을 별도 프로세스로 격리하고 PDF_TIMEOUT 초를 넘기면 프로세스를
    강제 종료하고 TimeoutError 를 던진다(호출부에서 errors 로 집계 후 다음 파일 진행).
    """
    req  = service.files().get_media(fileId=file_id)
    buf  = io.BytesIO()
    dl   = MediaIoBaseDownload(buf, req)
    done = False
    while not done:
        _, done = dl.next_chunk()
    return pdf_extract.extract_isolated(buf.getvalue(), PDF_TIMEOUT)


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


def _load_existing_modified() -> dict[str, str]:
    """drive 파일별 마지막 수집 시점의 modifiedTime → {source_id: modified}
    (변경 없는 파일은 재다운로드/임베딩을 건너뛰기 위함)"""
    out: dict[str, str] = {}
    offset, batch = 0, 1000
    while True:
        resp = (
            supabase.table("documents")
            .select("source_id,metadata")
            .eq("source", "drive")
            .eq("chunk_index", 0)
            .range(offset, offset + batch - 1)
            .execute()
        )
        rows = resp.data or []
        for row in rows:
            m = (row.get("metadata") or {}).get("modified")
            if m:
                out[row["source_id"]] = m
        if len(rows) < batch:
            break
        offset += batch
    log.info(f"기존 modifiedTime {len(out)}개 로드")
    return out


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

    existing          = _load_existing_hashes()
    existing_modified = _load_existing_modified()
    inserted = skipped = errors = 0

    for f in files:
        file_id   = f["id"]
        name      = f["name"]
        mime      = f["mimeType"]
        modified  = f.get("modifiedTime", "")
        url       = f.get("webViewLink", "")

        # (1) 파일명 기반 민감정보 제외 — 다운로드 전 차단
        if _is_sensitive_name(name):
            log.info(f"  민감문서 skip(파일명) [{name}]")
            skipped += 1
            continue

        # 변경 없는 파일은 다운로드/임베딩 생략 (modifiedTime 비교)
        if modified and existing_modified.get(file_id) == modified:
            skipped += 1
            continue

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

        # (2) 본문 기반 민감정보 안전망 — 주민번호·여권 감지 시 파일 전체 저장 안 함
        pii = _detect_pii(content)
        if pii:
            log.warning(f"  민감문서 skip(본문 {'/'.join(pii)}) [{name}]")
            skipped += 1
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
