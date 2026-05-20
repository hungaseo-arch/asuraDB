"""
Naver Band → Supabase 수집기
- Band Open API로 가입 밴드 목록 조회
- 각 밴드의 게시글 수집 → Markdown 변환
- 의미 단위 청킹 + 임베딩
- content_hash 비교 → 변경 없으면 skip
- 원본 삭제 감지 → Supabase 제거
- 30분 폴링
"""
import hashlib
import logging
import os
import sys
import time
from datetime import datetime, timezone

import requests
import schedule
from dotenv import load_dotenv
from sentence_transformers import SentenceTransformer
from supabase import create_client, Client as SupabaseClient

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))
from pipeline.chunker import chunk_markdown

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

BAND_ACCESS_TOKEN    = os.environ["BAND_ACCESS_TOKEN"]
SUPABASE_URL         = os.environ["SUPABASE_URL"]
SUPABASE_SERVICE_KEY = os.environ["SUPABASE_SERVICE_KEY"]
EMBEDDING_MODEL      = os.environ.get("EMBEDDING_MODEL", "paraphrase-multilingual-MiniLM-L12-v2")

BAND_API = "https://openapi.band.us"

supabase: SupabaseClient      = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
embedder: SentenceTransformer = SentenceTransformer(EMBEDDING_MODEL)


# ── Band API 헬퍼 ─────────────────────────────────────────────────────────────

def _get(path: str, params: dict | None = None) -> dict:
    params = params or {}
    params["access_token"] = BAND_ACCESS_TOKEN
    res = requests.get(f"{BAND_API}{path}", params=params, timeout=30)
    res.raise_for_status()
    return res.json()


def fetch_bands() -> list[dict]:
    data = _get("/v2/bands")
    return data.get("result_data", {}).get("bands", [])


def fetch_posts(band_key: str, after: str | None = None) -> tuple[list[dict], str | None]:
    params: dict = {"band_key": band_key, "limit": 20}
    if after:
        params["after"] = after
    data   = _get("/v2/band/posts", params)
    result = data.get("result_data", {})
    posts  = result.get("items", [])
    paging = result.get("paging", {})
    return posts, paging.get("next_params", {}).get("after")


# ── 변환 헬퍼 ─────────────────────────────────────────────────────────────────

def post_to_markdown(post: dict, band_name: str) -> str:
    author  = post.get("author", {}).get("name", "알 수 없음")
    created = post.get("created_at", "")[:10]
    content = post.get("content", "")
    photos  = post.get("photos", [])

    lines = [f"# {band_name} 게시글", f"작성자: {author} | {created}", "", content]
    if photos:
        lines += ["", f"첨부 이미지: {len(photos)}장"]
    return "\n".join(lines)


# ── Supabase 헬퍼 ─────────────────────────────────────────────────────────────

def _load_existing_hashes() -> dict[tuple[str, int], str]:
    hashes: dict[tuple[str, int], str] = {}
    offset, batch = 0, 1000
    while True:
        resp = (
            supabase.table("documents")
            .select("source_id,chunk_index,content_hash")
            .eq("source", "band")
            .range(offset, offset + batch - 1)
            .execute()
        )
        rows = resp.data or []
        for row in rows:
            hashes[(row["source_id"], row["chunk_index"])] = row["content_hash"]
        if len(rows) < batch:
            break
        offset += batch
    log.info(f"기존 Band 해시 {len(hashes)}개 로드")
    return hashes


def _remove_deleted_docs(current_ids: set[str]) -> int:
    existing_ids: set[str] = set()
    offset, batch = 0, 1000
    while True:
        resp = (
            supabase.table("documents")
            .select("source_id")
            .eq("source", "band")
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
        log.info("[band] 삭제된 게시글 없음")
        return 0

    ids_list = list(to_delete)
    for i in range(0, len(ids_list), 100):
        chunk = ids_list[i:i + 100]
        supabase.table("documents").delete().eq("source", "band").in_("source_id", chunk).execute()
    log.info(f"[band] 삭제된 게시글 {len(to_delete)}개 → Supabase에서 제거 완료")
    return len(to_delete)


# ── 메인 수집 ─────────────────────────────────────────────────────────────────

def collect() -> None:
    log.info("Band 수집 시작")
    bands = fetch_bands()
    log.info("밴드 %d개", len(bands))

    existing     = _load_existing_hashes()
    current_ids: set[str] = set()
    inserted = skipped = errors = 0

    for band in bands:
        band_key  = band["band_key"]
        band_name = band["name"]
        after     = None

        while True:
            posts, after = fetch_posts(band_key, after)
            for post in posts:
                post_key = post.get("post_key", "")
                if not post_key:
                    continue

                current_ids.add(post_key)

                md      = post_to_markdown(post, band_name)
                chunks  = chunk_markdown(md)
                created = post.get("created_at", datetime.now(timezone.utc).isoformat())
                url     = f"https://band.us/band/{band_key}/post/{post_key}"

                for idx, chunk in enumerate(chunks):
                    text = chunk["text"]
                    h    = hashlib.md5(text.encode()).hexdigest()

                    if existing.get((post_key, idx)) == h:
                        skipped += 1
                        continue

                    embedding = embedder.encode(text).tolist()
                    try:
                        supabase.table("documents").upsert(
                            {
                                "source":       "band",
                                "source_id":    post_key,
                                "chunk_index":  idx,
                                "chunk_type":   chunk["type"],
                                "title":        f"[{band_name}] {post.get('content', '')[:60]}",
                                "content":      text,
                                "content_hash": h,
                                "embedding":    embedding,
                                "source_url":   url,
                                "updated_at":   datetime.now(timezone.utc).isoformat(),
                                "metadata": {
                                    "band_key":  band_key,
                                    "band_name": band_name,
                                    "author":    post.get("author", {}).get("name"),
                                    "date":      created[:10] if created else None,
                                },
                            },
                            on_conflict="source,source_id,chunk_index",
                        ).execute()
                        inserted += 1
                    except Exception as e:
                        log.error(f"  upsert 실패 [band {post_key}] chunk {idx}: {e}")
                        errors += 1

            if not after:
                break
            time.sleep(0.5)

    _remove_deleted_docs(current_ids)

    log.info(f"Band 수집 완료 — inserted={inserted} skipped={skipped} errors={errors}")
    from collectors.heartbeat import record as _hb; _hb("band")


if __name__ == "__main__":
    collect()
    schedule.every(30).minutes.do(collect)
    while True:
        schedule.run_pending()
        time.sleep(60)
