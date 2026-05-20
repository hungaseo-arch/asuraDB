# AsuraDB 개발 지침서
## Personal Knowledge DB — Hybrid Search + Ollama MCP Agent

> 최종 수정: 2026년 5월
> 현재 상태: 로컬 Python/FastAPI + ChromaDB RAG 앱
> 목표 상태: Supabase Hybrid Search + Ollama MCP Agent 클라우드 시스템

---

## 1. 목표 아키텍처 (TO-BE)

```
┌─────────────────────────────────────────────────────────────────┐
│                         SOURCES                                 │
│                                                                 │
│  [현재] Notion │ UpNote │ Gmail │ Google Drive (4개)            │
│  [향후] + Obsidian Vault                                        │
└──────────────────────────┬──────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│                    INGESTION PIPELINE                           │
│                                                                 │
│  Markdown Parsing → Metadata Extraction → Chunking              │
│  → Link Analysis → Embedding → Supabase Upsert                  │
└──────────────────────────┬──────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│                       SUPABASE                                  │
│                                                                 │
│  PostgreSQL (문서/메타데이터) │ pgvector (임베딩) │ Storage      │
└──────────────────────────┬──────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│                    HYBRID SEARCH                                │
│                                                                 │
│  FTS (전문검색) + Vector (의미검색) + Metadata (필터)            │
│  → RRF (Reciprocal Rank Fusion) 점수 결합                       │
└──────────────────────────┬──────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│              Ollama / MCP / AI Agent                            │
│                                                                 │
│  질의응답 │ 문서 초안 │ 실무 분석 │ 이메일 작성                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. 현재 → 목표 스택 전환

| 레이어 | AS-IS (현재) | TO-BE (목표) |
|--------|-------------|-------------|
| 소스 | UpNote, Notion, Drive (3개) | Notion, UpNote, Gmail, Drive (4개) + Obsidian (향후) |
| 파싱 | 단순 텍스트 추출 | MD 파싱 + 메타데이터 추출 + 링크 분석 |
| 청킹 | 고정 크기 | 의미 단위 청킹 (헤딩/단락 기준) |
| 저장 | ChromaDB (로컬) | Supabase PostgreSQL + pgvector + Storage |
| 검색 | Vector 단일 | **FTS + Vector + Metadata 하이브리드 (RRF)** |
| AI | Ollama qwen3:8b RAG | Ollama + MCP Agent (도구 호출) |
| 프론트 | Vanilla HTML | Vue 3 + TailwindCSS (반응형) |
| 배포 | 로컬 전용 | 클라우드 (어디서나 접근) |

---

## 3. 소스별 수집 전략

| 소스 | 수집 방식 | 수집 주기 | 특이사항 |
|------|----------|----------|---------|
| **Notion** | Notion API (공식) | 30분 폴링 | DB 속성 → metadata 자동 매핑 |
| **UpNote** | MD 내보내기 + 폴더 감시 | 파일 변경 즉시 | #tag 자동 파싱 |
| **Gmail** | Gmail API (OAuth 2.0) | 15분 폴링 | PKDB/ 라벨 필터, 스레드 단위 청킹 |
| **Google Drive** | Drive API v3 (OAuth 2.0) | Drive Webhook (Push) | Docs→MD, PDF→텍스트 추출 |
| **Obsidian** | *(향후 추가 개발 예정)* | — | [[wikilink]] 그래프, frontmatter |

---

## 4. Ingestion Pipeline 상세

### 4-1. 전체 파이프라인 흐름

```
Raw Document (MD / API 응답 / 이메일)
        ↓
① Markdown Parsing
   - 헤딩 구조 인식 (H1~H3)
   - frontmatter YAML 파싱 (UpNote 태그, Notion 속성)
   - 코드블록 / 테이블 / 링크 보존

        ↓
② Metadata Extraction
   - source: 'notion' | 'upnote' | 'gmail' | 'drive'
   - title, date, tags, author, source_url
   - Gmail 전용: 발신자, 수신자, 스레드 ID

        ↓
③ Chunking (의미 단위)
   - 전략: 헤딩 기준 분할 → 500토큰 초과 시 단락 단위 재분할
   - 청크 간 50토큰 overlap (문맥 보존)
   - 단일 문서 최대 청크 수: 50개

        ↓
④ Link Analysis
   - Notion: 페이지 간 relation 추출
   - Gmail: 스레드 참조 체인 (In-Reply-To)
   - UpNote/Obsidian: [[wikilink]] 파싱 (향후 통합)

        ↓
⑤ Embedding 생성
   - 모델: paraphrase-multilingual-MiniLM-L12-v2 (기존 유지)
   - 차원: 384 / 한국어·인도네시아어 동시 지원

        ↓
⑥ Supabase Upsert
   - 중복 방지: source + source_id + chunk_index 기준
   - content_hash 비교 → 변경 없으면 스킵
```

### 4-2. Chunker 구현

```python
# pipeline/chunker.py
from typing import List
import re

MAX_TOKENS = 500
OVERLAP_TOKENS = 50

def chunk_markdown(content: str) -> List[dict]:
    """헤딩 기준 분할 → 초과 시 단락 단위 재분할"""
    chunks = []
    sections = re.split(r'\n(?=#{1,3} )', content)

    for section in sections:
        if estimate_tokens(section) <= MAX_TOKENS:
            chunks.append({"text": section, "type": "section"})
        else:
            paragraphs = section.split('\n\n')
            buffer, buf_tokens = [], 0
            for para in paragraphs:
                pt = estimate_tokens(para)
                if buf_tokens + pt > MAX_TOKENS and buffer:
                    chunks.append({"text": '\n\n'.join(buffer), "type": "paragraph"})
                    buffer = buffer[-1:]           # overlap: 마지막 단락 유지
                    buf_tokens = estimate_tokens(buffer[0]) if buffer else 0
                buffer.append(para)
                buf_tokens += pt
            if buffer:
                chunks.append({"text": '\n\n'.join(buffer), "type": "paragraph"})

    return chunks

def estimate_tokens(text: str) -> int:
    return len(text) // 4   # 간이 추정 (한국어: ~3자/token)
```

### 4-3. Gmail 수집기 구현

```python
# collectors/gmail_collector.py
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build

PKDB_LABEL = 'PKDB'   # Gmail 라벨 필터 (보안)

def collect_gmail(credentials: Credentials):
    service = build('gmail', 'v1', credentials=credentials)

    label_id = get_label_id(service, PKDB_LABEL)
    messages = service.users().messages().list(
        userId='me', labelIds=[label_id], maxResults=500
    ).execute()

    for msg in messages.get('messages', []):
        detail = service.users().messages().get(
            userId='me', id=msg['id'], format='full'
        ).execute()

        thread_id = detail.get('threadId')
        body      = extract_body(detail)
        meta      = extract_metadata(detail)   # 발신자, 날짜, 제목

        # 스레드 단위 upsert (thread_id를 source_id로 사용)
        upsert_to_supabase(
            source='gmail', source_id=thread_id,
            content=body, metadata=meta
        )
```

---

## 5. Supabase 스키마 설계

### 5-1. 핵심 테이블

```sql
-- 확장 활성화
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;   -- FTS 트라이그램 인덱스

-- 문서 청크 (Hybrid Search 핵심 테이블)
CREATE TABLE documents (
  id           UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  source       TEXT    NOT NULL,       -- 'notion'|'upnote'|'gmail'|'drive'
  source_id    TEXT    NOT NULL,       -- 원본 문서 ID
  chunk_index  INT     DEFAULT 0,      -- 청크 순서
  chunk_type   TEXT,                   -- 'section'|'paragraph'
  title        TEXT,
  content      TEXT    NOT NULL,
  content_hash TEXT,                   -- 변경 감지용 MD5
  embedding    VECTOR(384),            -- MiniLM 임베딩
  metadata     JSONB   DEFAULT '{}',   -- 태그, 날짜, 발신자 등
  source_url   TEXT,                   -- 원본 링크
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(source, source_id, chunk_index)
);

-- 문서 간 링크 관계
CREATE TABLE document_links (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  from_doc_id  UUID REFERENCES documents(id) ON DELETE CASCADE,
  to_source    TEXT,
  to_source_id TEXT,
  link_type    TEXT,    -- 'notion_relation'|'reply_to'|'wikilink'
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- 타이어 판매 데이터 (PT Ascendo 특화)
CREATE TABLE tire_sales (
  id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  branch      TEXT    NOT NULL,        -- 'surabaya'|'semarang'
  brand       TEXT    NOT NULL,        -- 'ASCENDO'|'AGR' 등
  sku         TEXT,
  qty         INTEGER,
  revenue     NUMERIC(15,2),
  margin_pct  NUMERIC(5,2),
  sale_date   DATE    NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

### 5-2. 인덱스

```sql
-- Vector 검색 (ivfflat)
CREATE INDEX idx_doc_embedding ON documents
  USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- FTS
CREATE INDEX idx_doc_fts   ON documents USING gin (to_tsvector('simple', content));
CREATE INDEX idx_doc_trgm  ON documents USING gin (content gin_trgm_ops);

-- Metadata 필터
CREATE INDEX idx_doc_source   ON documents (source);
CREATE INDEX idx_doc_metadata ON documents USING gin (metadata);
CREATE INDEX idx_doc_updated  ON documents (updated_at DESC);
```

### 5-3. Hybrid Search 함수 (RRF)

```sql
-- FTS + Vector → RRF (Reciprocal Rank Fusion) 결합
CREATE OR REPLACE FUNCTION hybrid_search(
  query_text      TEXT,
  query_embedding VECTOR(384),
  source_filter   TEXT    DEFAULT NULL,   -- NULL=전체
  tag_filter      TEXT    DEFAULT NULL,
  match_count     INT     DEFAULT 5
)
RETURNS TABLE(
  id UUID, source TEXT, title TEXT, content TEXT,
  source_url TEXT, metadata JSONB,
  vector_score FLOAT, fts_score FLOAT, rrf_score FLOAT
)
LANGUAGE SQL STABLE AS $$
  WITH vector_results AS (
    SELECT id,
           1 - (embedding <=> query_embedding) AS score,
           ROW_NUMBER() OVER (ORDER BY embedding <=> query_embedding) AS rank
    FROM documents
    WHERE (source_filter IS NULL OR source = source_filter)
      AND (tag_filter IS NULL OR metadata->>'tags' ILIKE '%' || tag_filter || '%')
    LIMIT 20
  ),
  fts_results AS (
    SELECT id,
           ts_rank(to_tsvector('simple', content),
                   plainto_tsquery('simple', query_text)) AS score,
           ROW_NUMBER() OVER (
             ORDER BY ts_rank(to_tsvector('simple', content),
                              plainto_tsquery('simple', query_text)) DESC
           ) AS rank
    FROM documents
    WHERE to_tsvector('simple', content) @@ plainto_tsquery('simple', query_text)
      AND (source_filter IS NULL OR source = source_filter)
    LIMIT 20
  ),
  rrf AS (
    SELECT COALESCE(v.id, f.id)    AS id,
           COALESCE(v.score, 0)    AS vector_score,
           COALESCE(f.score, 0)    AS fts_score,
           COALESCE(1.0/(60+v.rank),0) +
           COALESCE(1.0/(60+f.rank),0) AS rrf_score
    FROM vector_results v
    FULL OUTER JOIN fts_results f ON v.id = f.id
    ORDER BY rrf_score DESC
    LIMIT match_count
  )
  SELECT d.id, d.source, d.title, d.content,
         d.source_url, d.metadata,
         r.vector_score, r.fts_score, r.rrf_score
  FROM rrf r JOIN documents d ON r.id = d.id
  ORDER BY r.rrf_score DESC;
$$;
```

---

## 6. Ollama MCP Agent 설계

### 6-1. 기존 RAG → MCP Agent 전환

```
기존 RAG:  질문 → 벡터검색 → 컨텍스트 주입 → Ollama 답변
MCP Agent: 질문 → Ollama가 필요한 도구를 선택 호출 → 결과 종합 → 답변
           (Ollama가 능동적으로 다단계 추론 + 검색 수행)
```

### 6-2. MCP 도구 목록

```python
# mcp/tools.py
TOOLS = [
    {
        "name": "hybrid_search",
        "description": "Notion, UpNote, Gmail, Drive를 FTS+Vector 통합 검색합니다.",
        "input_schema": {
            "type": "object",
            "properties": {
                "query":         {"type": "string"},
                "source_filter": {"type": "string",  "description": "notion|upnote|gmail|drive"},
                "tag_filter":    {"type": "string"},
                "match_count":   {"type": "integer", "description": "기본 5"}
            },
            "required": ["query"]
        }
    },
    {
        "name": "get_document_links",
        "description": "문서와 연결된 관련 문서 목록을 가져옵니다.",
        "input_schema": {
            "type": "object",
            "properties": {"doc_id": {"type": "string"}},
            "required": ["doc_id"]
        }
    },
    {
        "name": "get_gmail_thread",
        "description": "Gmail 이메일 스레드 전체 내용을 가져옵니다.",
        "input_schema": {
            "type": "object",
            "properties": {"thread_id": {"type": "string"}},
            "required": ["thread_id"]
        }
    },
    {
        "name": "draft_email",
        "description": "이메일 초안을 작성합니다. 실제 발송은 하지 않습니다.",
        "input_schema": {
            "type": "object",
            "properties": {
                "to":      {"type": "string"},
                "subject": {"type": "string"},
                "context": {"type": "string", "description": "참고할 맥락"},
                "tone":    {"type": "string", "description": "formal|casual"}
            },
            "required": ["to", "subject"]
        }
    },
    {
        "name": "get_tire_sales",
        "description": "타이어 판매 실적 데이터를 조회합니다.",
        "input_schema": {
            "type": "object",
            "properties": {
                "branch":     {"type": "string", "description": "surabaya|semarang"},
                "brand":      {"type": "string"},
                "start_date": {"type": "string", "description": "YYYY-MM-DD"},
                "end_date":   {"type": "string", "description": "YYYY-MM-DD"}
            }
        }
    }
]
```

### 6-3. Agent 실행 루프

```python
# mcp/agent.py
import json
import httpx
import os

OLLAMA_BASE  = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL",    "qwen3:8b")

SYSTEM_PROMPT = """
당신은 PT Ascendo International 총괄 팀장의 개인 지식베이스 AI 어시스턴트입니다.

# 검색 전략
- 모든 질문에 먼저 hybrid_search로 관련 문서를 찾으세요
- 이메일 질문은 source_filter='gmail'로 우선 검색하세요
- 연관 문서는 get_document_links로 추가 맥락을 확보하세요
- 판매/실적 질문은 get_tire_sales를 호출하세요

# 답변 규칙
- 기본 응답 언어: 한국어
- 출처 명시 필수: [Notion], [Gmail], [Drive] 등
- 불확실한 정보는 "확인 필요" 표시
- 이메일 초안은 draft_email 도구 사용, 자동 발송 금지
"""

def run_agent(user_query: str) -> str:
    messages = [{"role": "user", "content": user_query}]

    with httpx.Client(timeout=httpx.Timeout(120)) as client:
        while True:
            resp = client.post(f"{OLLAMA_BASE}/api/chat", json={
                "model":    OLLAMA_MODEL,
                "messages": [{"role": "system", "content": SYSTEM_PROMPT}] + messages,
                "tools":    TOOLS,
                "stream":   False,
                "think":    False,
            })
            result  = resp.json()
            message = result.get("message", {})
            calls   = message.get("tool_calls") or []

            if not calls:
                return message.get("content", "")

            messages.append({"role": "assistant", "content": message.get("content", ""), "tool_calls": calls})

            for call in calls:
                fn     = call["function"]
                output = execute_tool(fn["name"], json.loads(fn.get("arguments", "{}")))
                messages.append({
                    "role":    "tool",
                    "content": json.dumps(output, ensure_ascii=False),
                })
```

---

## 7. 개발 단계별 로드맵

### Phase 1 — 기반 마이그레이션 (2~3주)

```
목표: ChromaDB → Supabase 이전, 기존 기능 동등성 확보

□ Supabase 프로젝트 생성 + 스키마/인덱스/함수 적용
□ ChromaDB → pgvector 마이그레이션 스크립트 실행
□ Vite + Vue 3 + TailwindCSS 프로젝트 초기화
□ Supabase Auth (Google OAuth) 로그인 구현
□ UpNote / Notion / Drive 수집기 → Supabase upsert로 교체
□ Vector 검색 → hybrid_search 함수로 전환

완료 기준: 기존 3개 소스 검색이 새 스택에서 정상 동작
```

### Phase 2 — Ingestion Pipeline 고도화 (1~2주)

```
목표: 단순 텍스트 추출 → 의미 단위 청킹 + 메타데이터 + 링크 분석

□ Markdown Parser + Chunker 구현 (섹션 4-2 참고)
□ Metadata Extractor 구현 (소스별 필드 매핑)
□ Link Analysis 구현 (Notion relation, 스레드 체인)
□ content_hash 변경 감지 → 불필요한 재임베딩 방지
□ 기존 데이터 재처리 (고도화 파이프라인으로 재수집)

완료 기준: 소스 필터 + 태그 필터 + FTS 검색 동작
```

### Phase 3 — Gmail 연동 (1~2주)

```
목표: Gmail PKDB 라벨 메일 수집 + 검색 + 초안 작성

□ Gmail OAuth 인증 흐름 구현
□ gmail_collector.py 작성 (PKDB 라벨 필터 + 스레드 청킹)
□ draft_email MCP 도구 연결 (발송은 수동)
□ Vue: Gmail 소스 필터 UI + 초안 작성 화면

완료 기준: "○○ 공급사 협상 메일 흐름 요약" 질의 동작
```

### Phase 4 — MCP Agent + 대시보드 (3~4주)

```
목표: 단순 RAG → Ollama MCP Agent 전환 + PT Ascendo 실무 특화

□ MCP Agent 실행 루프 구현 (섹션 6-3 참고)
□ 5개 MCP 도구 구현 및 테스트
□ 타이어 판매 데이터 입력/조회/차트 화면 (Vue)
□ 브랜드별/지점별 마진 분석 (AGR vs ASCENDO)
□ 월간 실적 요약 자동 생성
□ 모바일 반응형 최적화

완료 기준: "4월 AGR 마진 분석해줘" → Agent 도구 호출 후 분석 제공
```

### Phase 5 — Obsidian 연동 + 고도화 (향후)

```
□ Obsidian Vault 수집기 추가 개발
   - [[wikilink]] 파싱 + 문서 관계 그래프 구성
   - frontmatter YAML 메타데이터 파싱
   - Daily Notes 자동 인식
   - watchdog으로 Vault 변경 감지
□ Drive Webhook + Gmail Pub/Sub → 실시간 동기화
□ PWA: 홈 화면 추가, 오프라인 검색 캐시
□ 다국어 UI: 한국어 / 인도네시아어 전환
□ 검색 키워드 트래킹 + 개인화 가중치
```

---

## 8. 프로젝트 폴더 구조

```
AsuraDB/
├── frontend/                        # Vue 3 앱
│   ├── src/
│   │   ├── views/
│   │   │   ├── HomeView.vue         # 대시보드 (최근 검색, 핵심 지표)
│   │   │   ├── SearchView.vue       # 통합 Hybrid Search
│   │   │   ├── TireView.vue         # 타이어 비즈니스 관리
│   │   │   └── MailView.vue         # Gmail 초안 작성
│   │   ├── components/
│   │   ├── stores/                  # Pinia
│   │   └── router/
│   ├── vite.config.ts
│   └── tailwind.config.ts
│
├── pipeline/                        # Ingestion Pipeline
│   ├── parser.py                    # Markdown Parser
│   ├── chunker.py                   # 의미 단위 청킹
│   ├── metadata_extractor.py        # 소스별 메타데이터 추출
│   └── link_analyzer.py             # 문서 간 링크 분석
│
├── collectors/                      # 소스별 수집기
│   ├── notion_collector.py          # Notion API → Supabase
│   ├── upnote_collector.py          # MD 파일 감시 → Supabase
│   ├── gmail_collector.py           # Gmail API → Supabase (Phase 3)
│   ├── drive_collector.py           # Drive API → Supabase
│   └── obsidian_collector.py        # ← Phase 5 (향후 추가 개발)
│
├── mcp/                             # MCP Agent
│   ├── agent.py                     # Ollama Agent 실행 루프
│   ├── tools.py                     # 도구 정의
│   └── tool_handlers.py             # 도구 실행 핸들러
│
├── supabase/
│   ├── functions/
│   │   ├── hybrid-search/           # Hybrid Search 엔드포인트
│   │   └── agent/                   # MCP Agent 엔드포인트
│   └── migrations/
│       ├── 001_init.sql             # 기본 스키마
│       ├── 002_indexes.sql          # 인덱스
│       └── 003_functions.sql        # hybrid_search 함수
│
├── scripts/
│   └── migrate_chromadb.py          # ChromaDB → pgvector (1회)
│
├── .instructions.md
└── .env                             # API 키 (gitignore)
```

---

## 9. 핵심 환경변수 (.env)

```bash
# Supabase
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_ANON_KEY=eyJ...
SUPABASE_SERVICE_KEY=eyJ...         # 수집기 서버사이드 전용

# Ollama
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=qwen3:8b

# Google OAuth (Drive + Gmail 공용)
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
GOOGLE_REDIRECT_URI=http://localhost:5173/oauth/callback

# Notion
NOTION_API_KEY=secret_...
NOTION_DATABASE_IDS=db1_id,db2_id

# Embedding
EMBEDDING_MODEL=paraphrase-multilingual-MiniLM-L12-v2
```

---

## 10. ChromaDB → Supabase 마이그레이션 (1회)

```python
# scripts/migrate_chromadb.py
import chromadb, hashlib, os
from supabase import create_client

chroma    = chromadb.PersistentClient(path="./chroma_db")
supabase  = create_client(os.getenv("SUPABASE_URL"), os.getenv("SUPABASE_SERVICE_KEY"))
collection = chroma.get_collection("pkdb")
results   = collection.get(include=["documents", "embeddings", "metadatas"])

batch = []
for doc, emb, meta, id_ in zip(
    results["documents"], results["embeddings"],
    results["metadatas"],  results["ids"]
):
    batch.append({
        "source":       meta.get("source", "unknown"),
        "source_id":    id_,
        "chunk_index":  0,
        "title":        meta.get("title", ""),
        "content":      doc,
        "content_hash": hashlib.md5(doc.encode()).hexdigest(),
        "embedding":    emb,
        "metadata":     meta
    })
    if len(batch) >= 100:
        supabase.table("documents").upsert(
            batch, on_conflict="source,source_id,chunk_index"
        ).execute()
        print(f"  {len(batch)}건 마이그레이션...")
        batch = []

if batch:
    supabase.table("documents").upsert(
        batch, on_conflict="source,source_id,chunk_index"
    ).execute()

print("✅ ChromaDB → Supabase pgvector 마이그레이션 완료")
```

---

## 11. 보안 체크리스트

```
[ 인증 ]
□ Supabase RLS(Row Level Security) 활성화
□ SUPABASE_SERVICE_KEY 서버사이드 전용, 프론트 노출 금지
□ Google OAuth redirect_uri 프로덕션 도메인으로 제한

[ 데이터 수집 ]
□ Gmail: PKDB/ 라벨 메일만 수집 (전체 메일함 접근 금지)
□ 급여/개인정보 포함 문서 수집 제외 필터 적용
□ .env 파일 .gitignore 등록 필수

[ API ]
□ Ollama는 로컬 전용 (외부 노출 금지, localhost:11434)
□ Supabase Edge Function Rate Limit 설정
```

---

## 12. 개발 시작 커맨드

```bash
# 1. Vue 3 프로젝트 초기화
npm create vite@latest frontend -- --template vue-ts
cd frontend
npm install -D tailwindcss @tailwindcss/vite
npm install @supabase/supabase-js pinia vue-router

# 2. Supabase CLI
npm install -g supabase
supabase login && supabase init && supabase start
supabase db push   # 마이그레이션 적용

# 3. Python 수집기 의존성
pip install sentence-transformers supabase \
            google-api-python-client google-auth-oauthlib \
            notion-client watchdog pdfminer.six

# 4. ChromaDB → Supabase 마이그레이션 (1회)
python scripts/migrate_chromadb.py

# 5. 개발 서버
cd frontend && npm run dev
```

---

*Ollama 모델: qwen3:8b (검색/질의/MCP Agent) · 로컬 실행 (http://localhost:11434)*
*Obsidian Vault 연동은 Phase 5 (향후 추가 개발) 예정*
