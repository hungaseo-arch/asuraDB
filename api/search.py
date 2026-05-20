"""
Hybrid Search API — FastAPI
임베딩 생성 + Supabase hybrid_search RPC 호출
Ollama AI 검색 및 자동화 레포트 (스트리밍)
"""
import json
import os
import sys

from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

import httpx
from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from sentence_transformers import SentenceTransformer
from supabase import create_client

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

app = FastAPI(title="AsuraDB Search API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

embedder = SentenceTransformer(os.environ.get("EMBEDDING_MODEL", "paraphrase-multilingual-MiniLM-L12-v2"))
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

OLLAMA_BASE  = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL",    "qwen3:1.7b")


def _stream_ollama(system: str, user: str):
    """Ollama /api/chat 스트리밍 — <think> 블록 자동 제거"""
    in_think = False
    buf      = ""
    with httpx.Client(timeout=httpx.Timeout(120)) as client:
        with client.stream("POST", f"{OLLAMA_BASE}/api/chat", json={
            "model":    OLLAMA_MODEL,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user",   "content": user},
            ],
            "stream": True,
            "think":  False,
        }) as resp:
            for line in resp.iter_lines():
                if not line:
                    continue
                try:
                    text = json.loads(line).get("message", {}).get("content", "")
                except json.JSONDecodeError:
                    continue
                if not text:
                    continue
                buf += text
                out  = ""
                while True:
                    if not in_think:
                        s = buf.find("<think>")
                        if s == -1:
                            out += buf; buf = ""; break
                        out += buf[:s]; buf = buf[s + 7:]; in_think = True
                    else:
                        e = buf.find("</think>")
                        if e == -1:
                            buf = ""; break
                        buf = buf[e + 8:]; in_think = False
                if out:
                    yield out


def _search(q: str, source: str | None = None, tag: str | None = None, limit: int = 10) -> list[dict]:
    """hybrid_search RPC 호출 (벡터 + FTS, RRF 점수 정렬)"""
    embedding = embedder.encode(q).tolist()
    return supabase.rpc("hybrid_search", {
        "query_text":      q,
        "query_embedding": embedding,
        "source_filter":   source,
        "tag_filter":      tag,
        "match_count":     limit,
    }).execute().data or []


# ── 일반 검색 ──────────────────────────────────────────────────────────────

@app.get("/search")
def search(
    q:      str        = Query(..., min_length=1),
    source: str | None = Query(None),
    tag:    str | None = Query(None),
    limit:  int        = Query(10, ge=1, le=50),
):
    results = _search(q, source=source, tag=tag, limit=limit)
    return {"results": results, "query": q}


# ── AI 검색 ────────────────────────────────────────────────────────────────

class AiSearchRequest(BaseModel):
    q:     str
    limit: int = 8


def _build_context(docs: list[dict]) -> str:
    parts = []
    for i, d in enumerate(docs, 1):
        parts.append(f"[문서 {i}] 출처: {d['source']} | 제목: {d['title']}\n{d['content'][:600]}")
    return "\n\n".join(parts)


@app.post("/ai-search")
def ai_search(req: AiSearchRequest):
    docs = _search(req.q, limit=req.limit)

    context = _build_context(docs)
    system_prompt = (
        "당신은 개인 지식 DB 검색 어시스턴트입니다. "
        "아래 참조 문서를 바탕으로 질문에 한국어로 간결하고 정확하게 답변하세요. "
        "문서에 없는 내용은 추측하지 마세요."
    )
    user_prompt = f"참조 문서:\n{context}\n\n질문: {req.q}"

    def stream():
        sources_payload = []
        for d in docs:
            meta = d.get("metadata") or {}
            tags = meta.get("tags", []) if isinstance(meta, dict) else []
            sources_payload.append({
                "id":           d["id"],
                "source":       d["source"],
                "title":        d["title"],
                "content":      d["content"],
                "source_url":   d.get("source_url", ""),
                "rrf_score":    d.get("rrf_score", 0),
                "vector_score": d.get("vector_score", 0),
                "fts_score":    d.get("fts_score", 0),
                "chunk_type":   d.get("chunk_type", "section"),
                "tags":         tags,
                "metadata":     meta,
            })
        yield f"data: {json.dumps({'type': 'sources', 'sources': sources_payload}, ensure_ascii=False)}\n\n"

        for text in _stream_ollama(system_prompt, user_prompt):
            yield f"data: {json.dumps({'type': 'text', 'text': text}, ensure_ascii=False)}\n\n"

        yield "data: [DONE]\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream")


# ── 자동화 레포트 ──────────────────────────────────────────────────────────

class ReportRequest(BaseModel):
    topic: str = "인도네시아 타이어 시장 동향"


REPORT_QUERIES = [
    "인도네시아 AGR 타이어 시장 현황 주요 고객",
    "인도네시아 OTR 타이어 판매 동향",
    "인도네시아 TBR 트럭버스 타이어 거래처",
    "타이어 마진 가격 경쟁사 비교",
    "러버트랙 수요 현황 고객사",
]

REPORT_SYSTEM = (
    "당신은 인도네시아 타이어 시장 전문 애널리스트입니다. "
    "제공된 내부 문서(이메일, 미팅 기록, 드라이브 파일 등)를 분석하여 "
    "한국어로 구조화된 시장 동향 레포트를 작성하세요. "
    "각 섹션을 ## 헤딩으로 구분하고, 구체적인 수치와 고객사명을 포함하세요. "
    "문서에 없는 내용은 포함하지 마세요."
)


@app.post("/report/generate")
def report_generate(req: ReportRequest):
    all_docs: list[dict] = []
    seen_ids: set[str]   = set()
    for q in REPORT_QUERIES:
        for d in _search(q, limit=5):
            if d["id"] not in seen_ids:
                seen_ids.add(d["id"])
                all_docs.append(d)

    context     = _build_context(all_docs[:20])
    user_prompt = (
        f"주제: {req.topic}\n\n"
        f"참조 문서 ({len(all_docs)}건):\n{context}\n\n"
        "위 문서를 바탕으로 다음 섹션을 포함한 레포트를 작성하세요:\n"
        "## 시장 개요\n## 주요 고객사 동향\n## 제품별 현황\n## 경쟁사 분석\n## 시사점 및 제언"
    )

    def stream():
        for text in _stream_ollama(REPORT_SYSTEM, user_prompt):
            yield f"data: {json.dumps({'text': text}, ensure_ascii=False)}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream")


# ── 공통 ───────────────────────────────────────────────────────────────────

@app.get("/sources/status")
def sources_status():
    sources = ["notion", "upnote", "gmail", "drive", "calendar", "band"]

    hb_resp = supabase.table("collector_heartbeat").select("source,last_run").execute()
    heartbeats: dict[str, str] = {row["source"]: row["last_run"] for row in (hb_resp.data or [])}

    result: dict[str, str | None] = {}
    for source in sources:
        if source in heartbeats:
            result[source] = heartbeats[source]
        else:
            resp = (
                supabase.table("documents")
                .select("updated_at")
                .eq("source", source)
                .order("updated_at", desc=True)
                .limit(1)
                .execute()
            )
            result[source] = resp.data[0]["updated_at"] if resp.data else None
    return result


@app.get("/products")
def get_products():
    resp = (
        supabase.table("products")
        .select("id,item,brand,description,sku,wh_price,wh_price_set,unit")
        .eq("is_active", True)
        .order("brand")
        .order("description")
        .execute()
    )
    return {"products": resp.data or []}


# ── 견적서 저장/불러오기 ────────────────────────────────────────────────────────

class QuoteItemIn(BaseModel):
    line_no:    int
    product_id: str | None = None
    type:       str | None = None
    brand:      str | None = None
    description:str | None = None
    qty:        float = 0
    unit:       str   = "pcs"
    wh_price:   float = 0
    unit_price: float = 0
    discount:   float = 0


class QuoteIn(BaseModel):
    id:                  str | None = None
    customer_name:       str | None = None
    customer_po:         str | None = None
    sales_rep:           str | None = None
    warehouse:           str | None = None
    delivery_date:       str | None = None
    delivery_method:     str | None = None
    payment_terms:       str | None = None
    notes:               str | None = None
    additional_discount: float = 0
    status:              str   = "draft"
    currency:            str   = "USD"
    items: list[QuoteItemIn] = []


@app.post("/quotes")
def save_quote(req: QuoteIn):
    if req.id:
        supabase.table("quotes").update({
            "customer_name":       req.customer_name,
            "customer_po":         req.customer_po,
            "sales_rep":           req.sales_rep,
            "warehouse":           req.warehouse,
            "delivery_date":       req.delivery_date or None,
            "delivery_method":     req.delivery_method,
            "payment_terms":       req.payment_terms,
            "notes":               req.notes,
            "additional_discount": req.additional_discount,
            "status":              req.status,
            "currency":            req.currency,
        }).eq("id", req.id).execute()
        quote_id = req.id
        supabase.table("quote_items").delete().eq("quote_id", quote_id).execute()
    else:
        qn = supabase.rpc("next_quote_number", {}).execute().data
        ins = supabase.table("quotes").insert({
            "quote_number":        qn,
            "customer_name":       req.customer_name,
            "customer_po":         req.customer_po,
            "sales_rep":           req.sales_rep,
            "warehouse":           req.warehouse,
            "delivery_date":       req.delivery_date or None,
            "delivery_method":     req.delivery_method,
            "payment_terms":       req.payment_terms,
            "notes":               req.notes,
            "additional_discount": req.additional_discount,
            "status":              req.status,
            "currency":            req.currency,
        }).execute()
        quote_id = ins.data[0]["id"]

    if req.items:
        supabase.table("quote_items").insert([
            {
                "quote_id":   quote_id,
                "line_no":    item.line_no,
                "product_id": item.product_id or None,
                "type":       item.type,
                "brand":      item.brand,
                "description":item.description,
                "qty":        item.qty,
                "unit":       item.unit,
                "wh_price":   item.wh_price,
                "unit_price": item.unit_price,
                "discount":   item.discount,
            }
            for item in req.items
        ]).execute()

    quote = supabase.table("quotes").select("*").eq("id", quote_id).single().execute()
    return {"quote": quote.data}


@app.get("/quotes")
def list_quotes():
    resp = (
        supabase.table("quotes")
        .select("id,quote_number,customer_name,status,created_at,updated_at,additional_discount,currency")
        .order("created_at", desc=True)
        .execute()
    )
    return {"quotes": resp.data or []}


@app.get("/quotes/{quote_id}")
def get_quote(quote_id: str):
    quote = supabase.table("quotes").select("*").eq("id", quote_id).single().execute()
    items = (
        supabase.table("quote_items")
        .select("*")
        .eq("quote_id", quote_id)
        .order("line_no")
        .execute()
    )
    return {"quote": quote.data, "items": items.data or []}


@app.delete("/quotes/{quote_id}")
def delete_quote(quote_id: str):
    supabase.table("quotes").delete().eq("id", quote_id).execute()
    return {"ok": True}


@app.get("/health")
def health():
    return {"status": "ok"}
