"""
Gmail → Supabase 수집기
- PKDB 라벨 필터 (보안: 전체 메일함 접근 금지)
- 스레드 단위 청킹
- 저장 구조: 제목 / 보낸사람 / 날짜 / 본문 / 첨부파일 텍스트
- content_hash 변경 감지 → skip
- 원본 삭제 감지 → Supabase 제거
- 매일 오전 7시 수집
"""
import base64
import hashlib
import logging
import os
import re
import sys
import time
from datetime import datetime, timezone
from html.parser import HTMLParser

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
from collectors import pdf_extract

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

SUPABASE_URL         = os.environ["SUPABASE_URL"]
SUPABASE_SERVICE_KEY = os.environ["SUPABASE_SERVICE_KEY"]
EMBEDDING_MODEL      = os.environ.get("EMBEDDING_MODEL", "paraphrase-multilingual-MiniLM-L12-v2")
TOKEN_PATH           = os.path.join(os.path.dirname(__file__), "..", "token.json")
PKDB_LABEL           = "PKDB"

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

# PDF 첨부 추출 격리 subprocess 타임아웃(초). 초과 시 해당 첨부만 건너뜀.
PDF_TIMEOUT = int(os.environ.get("GMAIL_PDF_TIMEOUT", "90"))

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


def _get_label_id(service, label_name: str) -> str | None:
    resp = service.users().labels().list(userId="me").execute()
    for lbl in resp.get("labels", []):
        if lbl["name"].upper() == label_name.upper():
            return lbl["id"]
    return None


# ── 텍스트 추출 ────────────────────────────────────────────────────────────

class _HTMLTextExtractor(HTMLParser):
    """HTML → 순수 텍스트 (간격 보존)"""
    SKIP_TAGS = {"script", "style", "head"}

    def __init__(self):
        super().__init__()
        self._parts: list[str] = []
        self._skip = 0

    def handle_starttag(self, tag, attrs):
        if tag in self.SKIP_TAGS:
            self._skip += 1
        if tag in {"br", "p", "div", "tr", "li", "h1", "h2", "h3", "h4", "h5", "h6"}:
            self._parts.append("\n")

    def handle_endtag(self, tag):
        if tag in self.SKIP_TAGS:
            self._skip = max(0, self._skip - 1)

    def handle_data(self, data):
        if not self._skip:
            self._parts.append(data)

    def get_text(self) -> str:
        raw = "".join(self._parts)
        lines = [ln.strip() for ln in raw.splitlines()]
        return "\n".join(ln for ln in lines if ln)


def _html_to_text(html: str) -> str:
    parser = _HTMLTextExtractor()
    try:
        parser.feed(html)
        return parser.get_text()
    except Exception:
        return re.sub(r"<[^>]+>", " ", html)


def _decode_part(part: dict) -> str:
    data = part.get("body", {}).get("data", "")
    if not data:
        return ""
    return base64.urlsafe_b64decode(data + "==").decode("utf-8", errors="replace")


def _get_body(payload: dict) -> str:
    """메시지 payload에서 본문 텍스트 추출 (text/plain 우선, 없으면 HTML 변환)"""
    mime  = payload.get("mimeType", "")
    parts = payload.get("parts", [])

    if mime == "text/plain":
        return _decode_part(payload)
    if mime == "text/html":
        return _html_to_text(_decode_part(payload))

    # multipart: text/plain 먼저 찾고, 없으면 html
    plain = html = ""
    for part in parts:
        t = _get_body(part)
        pmime = part.get("mimeType", "")
        if pmime == "text/plain" and not plain:
            plain = t
        elif pmime == "text/html" and not html:
            html = t
        elif t and not plain and not html:
            plain = t
    return plain or html


def _extract_attachment_text(service, user_id: str, msg_id: str, part: dict) -> tuple[str, str]:
    """
    첨부파일 텍스트 추출. (filename, text) 반환.
    지원: text/plain, text/html, application/pdf
    """
    filename = part.get("filename", "")
    mime     = part.get("mimeType", "")
    body     = part.get("body", {})
    att_id   = body.get("attachmentId")
    raw_data = body.get("data", "")

    # 데이터 획득
    if att_id:
        try:
            resp     = service.users().messages().attachments().get(
                userId=user_id, messageId=msg_id, id=att_id
            ).execute()
            raw_data = resp.get("data", "")
        except Exception as e:
            log.debug(f"    첨부파일 다운로드 실패 [{filename}]: {e}")
            return filename, ""

    if not raw_data:
        return filename, ""

    raw_bytes = base64.urlsafe_b64decode(raw_data + "==")

    if mime in ("text/plain", "text/html"):
        text = raw_bytes.decode("utf-8", errors="replace")
        return filename, (_html_to_text(text) if mime == "text/html" else text)

    if mime == "application/pdf":
        # 격리 subprocess 로 추출 — 일부 PDF 가 pdfminer 레이아웃 분석에서 폭주(O(n^2),
        # 수 시간·수 GB)해 수집 전체가 멈추는 것을 방지(배경: collectors/pdf_extract.py).
        try:
            return filename, pdf_extract.extract_isolated(raw_bytes, PDF_TIMEOUT)
        except Exception as e:  # TimeoutError/RuntimeError 포함
            log.debug(f"    PDF 추출 실패/건너뜀 [{filename}]: {e}")
            return filename, ""

    return filename, ""


def _collect_attachments(service, user_id: str, msg_id: str, payload: dict) -> list[tuple[str, str]]:
    """메시지 전체에서 첨부파일 (filename, text) 목록 수집"""
    results: list[tuple[str, str]] = []
    mime  = payload.get("mimeType", "")
    parts = payload.get("parts", [])

    is_attachment = bool(payload.get("filename")) or "attachment" in (
        {h["name"].lower(): h["value"] for h in payload.get("headers", [])}.get("content-disposition", "")
    )

    if is_attachment and mime in ("text/plain", "text/html", "application/pdf"):
        fname, text = _extract_attachment_text(service, user_id, msg_id, payload)
        if text.strip():
            results.append((fname, text.strip()))
        return results

    for part in parts:
        results.extend(_collect_attachments(service, user_id, msg_id, part))

    return results


# ── 스레드 → Markdown ──────────────────────────────────────────────────────

def _thread_to_markdown(service, thread_id: str) -> tuple[str, dict]:
    """
    스레드 전체를 구조화된 Markdown으로 변환.
    저장 형식:
        # 제목
        **보낸사람:** ...
        **날짜:** ...

        ## 본문
        ...

        ## 첨부파일: filename.pdf
        ...
        ---
    """
    thread = service.users().threads().get(userId="me", id=thread_id, format="full").execute()
    msgs   = thread.get("messages", [])
    lines: list[str] = []
    meta: dict = {}
    att_filenames: list[str] = []

    for i, msg in enumerate(msgs):
        msg_id  = msg["id"]
        headers = {h["name"]: h["value"] for h in msg.get("payload", {}).get("headers", [])}
        subject = headers.get("Subject", "(제목 없음)")
        sender  = headers.get("From", "")
        date    = headers.get("Date", "")
        body    = _get_body(msg.get("payload", {})).strip()
        atts    = _collect_attachments(service, "me", msg_id, msg.get("payload", {}))

        if i == 0:
            meta = {
                "subject":         subject,
                "from":            sender,
                "date":            date,
                "thread_id":       thread_id,
                "label":           PKDB_LABEL,
                "has_attachments": bool(atts),
            }
            lines.append(f"# {subject}\n")

        lines.append(f"**보낸사람:** {sender}  ")
        lines.append(f"**날짜:** {date}\n")

        if body:
            lines.append("## 본문\n")
            lines.append(body)

        for fname, att_text in atts:
            att_filenames.append(fname)
            label = f"## 첨부파일: {fname}" if fname else "## 첨부파일"
            lines.append(f"\n{label}\n")
            lines.append(att_text)

        lines.append("\n---")

    if att_filenames:
        meta["attachments"] = att_filenames

    return "\n".join(lines).strip(), meta


# ── Supabase 헬퍼 ──────────────────────────────────────────────────────────

def _load_existing_hashes() -> dict[tuple[str, int], str]:
    hashes: dict[tuple[str, int], str] = {}
    offset, batch = 0, 1000
    while True:
        resp = (
            supabase.table("documents")
            .select("source_id,chunk_index,content_hash")
            .eq("source", "gmail")
            .range(offset, offset + batch - 1)
            .execute()
        )
        rows = resp.data or []
        for row in rows:
            hashes[(row["source_id"], row["chunk_index"])] = row["content_hash"]
        if len(rows) < batch:
            break
        offset += batch
    log.info(f"기존 Gmail 해시 {len(hashes)}개 로드")
    return hashes


def _remove_deleted_docs(current_ids: set[str]) -> int:
    existing_ids: set[str] = set()
    offset, batch = 0, 1000
    while True:
        resp = (
            supabase.table("documents")
            .select("source_id")
            .eq("source", "gmail")
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
        log.info("[gmail] 삭제된 스레드 없음")
        return 0

    ids_list = list(to_delete)
    for i in range(0, len(ids_list), 100):
        chunk = ids_list[i:i + 100]
        supabase.table("documents").delete().eq("source", "gmail").in_("source_id", chunk).execute()
    log.info(f"[gmail] 삭제된 스레드 {len(to_delete)}개 → Supabase에서 제거 완료")
    return len(to_delete)


# ── 수집 메인 ──────────────────────────────────────────────────────────────

def collect_all():
    log.info("=== Gmail 전체 수집 시작 ===")
    creds   = _get_credentials()
    service = build("gmail", "v1", credentials=creds)

    label_id = _get_label_id(service, PKDB_LABEL)
    if not label_id:
        # 라벨이 없으면 수집 대상을 특정할 수 없음 → 기존 문서 보호를 위해 중단.
        # (과거 동작: '받은편지함 최근 500개' 폴백 후 그 외 전량 prune → 데이터 손실 위험)
        log.error(
            f"'{PKDB_LABEL}' 라벨이 없어 Gmail 수집을 중단합니다 (기존 문서 보호). "
            f"수집할 메일에 '{PKDB_LABEL}' 라벨을 지정한 뒤 다시 실행하세요."
        )
        return

    # 라벨된 스레드 전체 수집 (페이지네이션 — 500개 cap 제거)
    threads: list[dict] = []
    page_token = None
    while True:
        resp = service.users().threads().list(
            userId="me", labelIds=[label_id], maxResults=500, pageToken=page_token,
        ).execute()
        threads.extend(resp.get("threads", []))
        page_token = resp.get("nextPageToken")
        if not page_token:
            break
    log.info(f"수집 대상 스레드 {len(threads)}개")

    current_ids = {t["id"] for t in threads}
    _remove_deleted_docs(current_ids)

    existing = _load_existing_hashes()
    inserted = skipped = errors = 0

    for t in threads:
        thread_id = t["id"]
        try:
            content, meta = _thread_to_markdown(service, thread_id)
        except Exception as e:
            log.warning(f"  스레드 읽기 실패 {thread_id}: {e}")
            errors += 1
            continue

        content = content.replace("\x00", "").strip()
        if not content:
            continue

        title  = meta.get("subject", thread_id)
        chunks = chunk_markdown(content)

        for idx, chunk in enumerate(chunks):
            text = chunk["text"]
            h    = hashlib.md5(text.encode()).hexdigest()

            if existing.get((thread_id, idx)) == h:
                skipped += 1
                continue

            embedding = embedder.encode(text).tolist()
            for attempt in range(4):
                try:
                    supabase.table("documents").upsert(
                        {
                            "source":       "gmail",
                            "source_id":    thread_id,
                            "chunk_index":  idx,
                            "chunk_type":   chunk["type"],
                            "title":        title,
                            "content":      text,
                            "content_hash": h,
                            "embedding":    embedding,
                            "metadata":     meta,
                            "source_url":   f"https://mail.google.com/mail/u/0/#all/{thread_id}",
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

        att_info = f" 첨부={meta.get('attachments', [])}" if meta.get("has_attachments") else ""
        log.info(f"  [{title[:40]}] chunks={len(chunks)} inserted={inserted} skipped={skipped}{att_info}")

    log.info(f"=== Gmail 수집 완료 — inserted={inserted} skipped={skipped} errors={errors} ===")
    from collectors.heartbeat import record as _hb; _hb("gmail")


if __name__ == "__main__":
    collect_all()

    schedule.every().day.at("07:00").do(collect_all)
    log.info("스케줄러 시작 — 매일 오전 7시 수집")

    while True:
        schedule.run_pending()
        time.sleep(60)
