"""
Notion → Supabase 수집기
- Notion API로 DB 페이지 목록 조회
- 블록 본문 → Markdown 변환
- 의미 단위 청킹 + 임베딩
- content_hash 비교 → 변경 없으면 skip
- 30분 폴링
"""
import hashlib
import logging
import os
import sys
import time
from datetime import datetime, timezone
from typing import Any

import schedule
from dotenv import load_dotenv
from notion_client import Client
from sentence_transformers import SentenceTransformer
from supabase import create_client, Client as SupabaseClient

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))
from pipeline.chunker import chunk_markdown

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

# ── 환경변수 ──────────────────────────────────────────────────────────────
NOTION_API_KEY     = os.environ["NOTION_API_KEY"]
NOTION_DATABASE_IDS = os.environ["NOTION_DATABASE_IDS"]   # 쉼표 구분
SUPABASE_URL       = os.environ["SUPABASE_URL"]
SUPABASE_SERVICE_KEY = os.environ["SUPABASE_SERVICE_KEY"]
EMBEDDING_MODEL    = os.environ.get("EMBEDDING_MODEL", "paraphrase-multilingual-MiniLM-L12-v2")

notion:   Client         = Client(auth=NOTION_API_KEY)
supabase: SupabaseClient = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
embedder: SentenceTransformer = SentenceTransformer(EMBEDDING_MODEL)


# ── Notion 블록 → Markdown ────────────────────────────────────────────────

def _rich_text(rt_list: list) -> str:
    return "".join(r.get("plain_text", "") for r in rt_list)


def blocks_to_markdown(blocks: list, depth: int = 0) -> str:
    lines = []
    indent = "  " * depth

    for block in blocks:
        btype = block["type"]
        b = block[btype]

        if btype == "paragraph":
            text = _rich_text(b.get("rich_text", []))
            lines.append(f"{indent}{text}" if text else "")

        elif btype in ("heading_1", "heading_2", "heading_3"):
            level = {"heading_1": "#", "heading_2": "##", "heading_3": "###"}[btype]
            text = _rich_text(b.get("rich_text", []))
            lines.append(f"{level} {text}")

        elif btype == "bulleted_list_item":
            text = _rich_text(b.get("rich_text", []))
            lines.append(f"{indent}- {text}")

        elif btype == "numbered_list_item":
            text = _rich_text(b.get("rich_text", []))
            lines.append(f"{indent}1. {text}")

        elif btype == "to_do":
            checked = "x" if b.get("checked") else " "
            text = _rich_text(b.get("rich_text", []))
            lines.append(f"{indent}- [{checked}] {text}")

        elif btype == "code":
            lang = b.get("language", "")
            text = _rich_text(b.get("rich_text", []))
            lines.append(f"```{lang}\n{text}\n```")

        elif btype == "quote":
            text = _rich_text(b.get("rich_text", []))
            lines.append(f"> {text}")

        elif btype == "divider":
            lines.append("---")

        elif btype == "image":
            url = b.get("file", {}).get("url") or b.get("external", {}).get("url", "")
            caption = _rich_text(b.get("caption", []))
            lines.append(f"![{caption}]({url})")

        elif btype == "child_page":
            lines.append(f"[{b.get('title', '')}]")

        elif btype == "callout":
            text = _rich_text(b.get("rich_text", []))
            icon = b.get("icon", {}).get("emoji", "")
            lines.append(f"> {icon} {text}")

        elif btype == "toggle":
            text = _rich_text(b.get("rich_text", []))
            lines.append(f"**{text}**")

        # 중첩 블록 재귀 처리
        if block.get("has_children"):
            children = _fetch_all_blocks(block["id"])
            lines.append(blocks_to_markdown(children, depth + 1))

    return "\n\n".join(l for l in lines if l is not None)


def _fetch_all_blocks(block_id: str) -> list:
    """페이지네이션을 처리하며 모든 하위 블록 반환"""
    blocks, cursor = [], None
    while True:
        kwargs: dict[str, Any] = {"block_id": block_id}
        if cursor:
            kwargs["start_cursor"] = cursor
        resp = notion.blocks.children.list(**kwargs)
        blocks.extend(resp.get("results", []))
        if not resp.get("has_more"):
            break
        cursor = resp.get("next_cursor")
    return blocks


# ── Notion 속성 → metadata 매핑 ───────────────────────────────────────────

def extract_properties(props: dict) -> dict:
    """Notion 페이지 속성을 flat dict로 변환"""
    meta: dict[str, Any] = {}

    for key, val in props.items():
        ptype = val["type"]

        if ptype == "title":
            meta["title"] = _rich_text(val["title"])

        elif ptype == "rich_text":
            meta[key] = _rich_text(val["rich_text"])

        elif ptype == "select":
            meta[key] = val["select"]["name"] if val["select"] else None

        elif ptype == "multi_select":
            meta[key] = [o["name"] for o in val["multi_select"]]

        elif ptype == "date":
            if val["date"]:
                meta[key] = val["date"]["start"]

        elif ptype == "number":
            meta[key] = val["number"]

        elif ptype == "checkbox":
            meta[key] = val["checkbox"]

        elif ptype == "url":
            meta[key] = val["url"]

        elif ptype == "email":
            meta[key] = val["email"]

        elif ptype == "phone_number":
            meta[key] = val["phone_number"]

        elif ptype == "formula":
            fval = val["formula"]
            meta[key] = fval.get(fval.get("type", "string"))

        elif ptype == "relation":
            meta[key] = [r["id"] for r in val["relation"]]

        elif ptype in ("created_time", "last_edited_time"):
            meta[key] = val[ptype]

        elif ptype == "created_by":
            meta[key] = val["created_by"].get("id")

        elif ptype == "status":
            meta[key] = val["status"]["name"] if val["status"] else None

    return meta


# ── ID 타입 판별 (database vs page) ──────────────────────────────────────

import httpx as _httpx

def _notion_object_type(object_id: str) -> str:
    """'database' | 'page' | 'unknown' 반환"""
    headers = {
        "Authorization": f"Bearer {NOTION_API_KEY}",
        "Notion-Version": "2022-06-28",
    }
    for endpoint in (f"databases/{object_id}", f"pages/{object_id}"):
        r = _httpx.get(f"https://api.notion.com/v1/{endpoint}", headers=headers, timeout=10)
        if r.status_code == 200:
            return r.json().get("object", "unknown")
    return "unknown"


def _query_database_pages(database_id: str) -> list:
    headers = {
        "Authorization": f"Bearer {NOTION_API_KEY}",
        "Notion-Version": "2022-06-28",
        "Content-Type": "application/json",
    }
    pages, cursor = [], None
    while True:
        body: dict[str, Any] = {}
        if cursor:
            body["start_cursor"] = cursor
        r = _httpx.post(
            f"https://api.notion.com/v1/databases/{database_id}/query",
            headers=headers, json=body, timeout=15
        )
        r.raise_for_status()
        data = r.json()
        pages.extend(data.get("results", []))
        if not data.get("has_more"):
            break
        cursor = data.get("next_cursor")
    return pages


def _collect_all_descendant_pages(root_id: str) -> list[str]:
    """BFS로 모든 하위 페이지/DB ID를 깊이 제한 없이 수집"""
    headers = {
        "Authorization": f"Bearer {NOTION_API_KEY}",
        "Notion-Version": "2022-06-28",
    }
    collected: list[str] = []
    queue = [root_id]
    visited: set[str] = {root_id}

    while queue:
        current_id = queue.pop(0)
        cursor = None

        while True:
            params: dict[str, Any] = {}
            if cursor:
                params["start_cursor"] = cursor
            r = _httpx.get(
                f"https://api.notion.com/v1/blocks/{current_id}/children",
                headers=headers, params=params, timeout=15
            )
            if r.status_code != 200:
                break
            data = r.json()
            for block in data.get("results", []):
                btype = block["type"]
                if btype in ("child_page", "child_database"):
                    child_id = block["id"]
                    if child_id not in visited:
                        visited.add(child_id)
                        collected.append(child_id)
                        queue.append(child_id)   # 하위의 하위도 탐색
            if not data.get("has_more"):
                break
            cursor = data.get("next_cursor")

    return collected


def _remove_deleted_docs(current_ids: set[str]) -> int:
    """Notion에서 삭제된 페이지를 Supabase에서 제거"""
    existing_ids: set[str] = set()
    offset, batch = 0, 1000
    while True:
        resp = (
            supabase.table("documents")
            .select("source_id")
            .eq("source", "notion")
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
        log.info("[notion] 삭제된 페이지 없음")
        return 0

    ids_list = list(to_delete)
    for i in range(0, len(ids_list), 100):
        chunk = ids_list[i:i + 100]
        supabase.table("documents").delete().eq("source", "notion").in_("source_id", chunk).execute()
    log.info(f"[notion] 삭제된 페이지 {len(to_delete)}개 → Supabase에서 제거 완료")
    return len(to_delete)


def _existing_hash(source_id: str, chunk_index: int) -> str | None:
    resp = (
        supabase.table("documents")
        .select("content_hash")
        .eq("source", "notion")
        .eq("source_id", source_id)
        .eq("chunk_index", chunk_index)
        .limit(1)
        .execute()
    )
    rows = resp.data if resp else []
    return rows[0]["content_hash"] if rows else None


# ── 단일 페이지 upsert ────────────────────────────────────────────────────

def _upsert_page(page_id: str) -> tuple[int, int]:
    """페이지 1개를 수집해 Supabase에 upsert. (inserted, skipped) 반환"""
    inserted = skipped = 0

    # 페이지 메타데이터
    headers = {
        "Authorization": f"Bearer {NOTION_API_KEY}",
        "Notion-Version": "2022-06-28",
    }
    r = _httpx.get(f"https://api.notion.com/v1/pages/{page_id}", headers=headers, timeout=10)
    if r.status_code != 200:
        log.warning(f"페이지 조회 실패 {page_id}: {r.status_code}")
        return 0, 0

    page     = r.json()
    page_url = page.get("url", "")
    props    = page.get("properties", {})
    metadata = extract_properties(props)
    title    = metadata.get("title") or page_id

    # Markdown 본문
    md_resp = notion.pages.retrieve_markdown(page_id)
    content = (md_resp.get("markdown") or "").strip()

    if not content:
        log.debug(f"  빈 페이지 skip: {title}")
        return 0, 0

    chunks = chunk_markdown(content)

    for idx, chunk in enumerate(chunks):
        text = chunk["text"]
        h    = hashlib.md5(text.encode()).hexdigest()

        if _existing_hash(page_id, idx) == h:
            skipped += 1
            continue

        embedding = embedder.encode(text).tolist()
        supabase.table("documents").upsert(
            {
                "source":       "notion",
                "source_id":    page_id,
                "chunk_index":  idx,
                "chunk_type":   chunk["type"],
                "title":        title,
                "content":      text,
                "content_hash": h,
                "embedding":    embedding,
                "metadata":     metadata,
                "source_url":   page_url,
                "updated_at":   datetime.now(timezone.utc).isoformat(),
            },
            on_conflict="source,source_id,chunk_index",
        ).execute()
        inserted += 1

    log.info(f"  [{title}] chunks={len(chunks)} inserted={inserted} skipped={skipped}")
    return inserted, skipped


# ── 메인 수집 로직 ────────────────────────────────────────────────────────

def collect_entry(entry_id: str) -> set[str]:
    """DB 또는 페이지 ID를 받아 수집. 수집된 page_id 집합 반환"""
    obj_type = _notion_object_type(entry_id)
    total_inserted = total_skipped = 0
    collected_ids: set[str] = set()

    if obj_type == "database":
        log.info(f"DB 수집 시작: {entry_id}")
        pages = _query_database_pages(entry_id)
        for page in pages:
            pid = page["id"]
            collected_ids.add(pid)
            i, s = _upsert_page(pid)
            total_inserted += i
            total_skipped  += s
        log.info(f"DB 완료: {entry_id} — inserted={total_inserted} skipped={total_skipped}")

    elif obj_type == "page":
        log.info(f"페이지 수집 시작: {entry_id}")
        collected_ids.add(entry_id)
        i, s = _upsert_page(entry_id)
        total_inserted += i
        total_skipped  += s
        children = _collect_all_descendant_pages(entry_id)
        for child_id in children:
            collected_ids.add(child_id)
            ci, cs = _upsert_page(child_id)
            total_inserted += ci
            total_skipped  += cs
        log.info(f"페이지 완료: {entry_id} — inserted={total_inserted} skipped={total_skipped}")

    else:
        log.error(f"알 수 없는 ID: {entry_id}")

    return collected_ids


def collect_all():
    log.info("=== Notion 전체 수집 시작 ===")
    entry_ids = [d.strip() for d in NOTION_DATABASE_IDS.split(",") if d.strip()]
    all_collected_ids: set[str] = set()
    for entry_id in entry_ids:
        try:
            ids = collect_entry(entry_id)
            all_collected_ids.update(ids)
        except Exception as e:
            log.error(f"수집 실패 {entry_id}: {e}", exc_info=True)
    _remove_deleted_docs(all_collected_ids)
    log.info("=== Notion 전체 수집 완료 ===")
    from collectors.heartbeat import record as _hb; _hb("notion")


# ── 실행 진입점 ───────────────────────────────────────────────────────────

if __name__ == "__main__":
    collect_all()

    schedule.every().day.at("08:00").do(collect_all)
    log.info("스케줄러 시작 — 매일 오전 7시 수집")

    while True:
        schedule.run_pending()
        time.sleep(60)
