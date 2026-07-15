# AsuraDB 개발 지침서
## Personal Knowledge DB — Hybrid Search + Claude AI Agent

> 최종 수정: 2026년 6월 2일 (Supabase Auth + RLS to authenticated · Claude 단일화 · 견적서 UI 정리 반영)
> 현재 상태: Supabase + Vue 3 운영 중 (하이브리드 검색, 견적서, 지표 모니터링, 마진 분석, 타이어 수입량)
> 목표 상태: Claude AI Agent 고도화 + Obsidian 연동

---

## 📚 문서 구성 (docs/)

| 문서 | 내용 |
|---|---|
| **AsuraDB_Development_Guide.md** (본 문서) | 아키텍처 · 스키마 · 파이프라인 · 환경변수 · **Supabase 연결·보안(§11)** · 로드맵 · 구현현황 · **부록 A. React→Vue 마이그레이션** |
| **AsuraDB_지표수집_가이드.md** | 외부 거시·시장 지표 24종 수집 가이드 (원자재·환율·운임·거시경제·자사 영업) |
| **웹사이트_운영_변경이력.md** | Monitor/Margin 등 **월간 비즈니스 데이터** 갱신 절차 + 변경이력(changelog) |

> 연결·보안은 본 문서 §11로 통합(구 `AsuraDB_supabase연결.md`), 마이그레이션 노트는 부록 A로 통합(구 `MIGRATION.md`)되었습니다.

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
│              Claude API / AI Agent                              │
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
| AI | Claude Haiku RAG (`api/search.py`) | Claude Agent (MCP 도구 호출) |
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

**tire_imports** — 인도네시아 월간 타이어 수입통계 (BPS EXIM 기반, `TireImport.vue`).

```sql
CREATE TABLE tire_imports (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  year       INT  NOT NULL CHECK (year BETWEEN 2020 AND 2099),
  month      INT  NOT NULL CHECK (month BETWEEN 1 AND 12),
  hs_code    TEXT NOT NULL,          -- BTKI/AHTN 2022 8자리 (마스터 32종)
  category   TEXT NOT NULL,          -- 16종: pc,lt,tb,mc,bc,agr,ind,mining_truck,otr,
                                     --        aircraft,other,retread,used,solid,flap,tube
  country    TEXT NOT NULL DEFAULT 'ALL',   -- 원산지(영문 정규화). ALL=합계
  value_usd  NUMERIC DEFAULT 0,
  weight_kg  NUMERIC DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (year, month, hs_code, country)
);
```
- **최신 스냅샷 = `supabase/migrations/add_tire_imports.sql`** (16종 CHECK). 이력 마이그레이션(add_agr_category / add_pc_mc_categories / alter_categories_v3)은 기존 DB 단계 승격용이며 신규 설치엔 base 파일만 실행.
- **적재 경로 3가지**: ① API 자동 — `collectors/bps_import_collector.py`(BPS dataexim, 16종씩 분할·20종/요청 한도) 또는 프런트 [최신데이터가져오기]→`POST /collect/tire-imports`; ② XLSX 수동 — `scripts/ingest-bps-file.mjs`(포털 다운로드 교차표); ③ CSV 붙여넣기(TireImport.vue). `BPS_API_KEY` 필요(§9).
- **공유 데이터(SSOT)**: HS 마스터 32종 = `src/data/hsMaster.json`(웹·py·mjs 3소비자 공유), 국가 표기 정규화 = `data/country_alias.json`(py·mjs 공유). 카테고리 CHECK 변경 시 이 JSON도 함께 갱신.

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

## 6. Claude AI Agent 설계

### 6-1. 기존 RAG → Claude Agent 전환

```
기존 RAG:   질문 → 벡터검색 → 컨텍스트 주입 → Claude 답변
Claude Agent: 질문 → Claude가 필요한 도구를 선택 호출 → 결과 종합 → 답변
              (Claude가 능동적으로 다단계 추론 + 검색 수행)
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
import anthropic
import os

_claude      = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
CLAUDE_MODEL = os.environ.get("CLAUDE_MODEL_AGENT", "claude-sonnet-4-6")

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

    while True:
        resp = _claude.messages.create(
            model=CLAUDE_MODEL,
            max_tokens=4096,
            system=SYSTEM_PROMPT,
            tools=TOOLS,
            messages=messages,
        )

        if resp.stop_reason != "tool_use":
            return next(
                (b.text for b in resp.content if hasattr(b, "text")), ""
            )

        messages.append({"role": "assistant", "content": resp.content})

        tool_results = []
        for block in resp.content:
            if block.type == "tool_use":
                output = execute_tool(block.name, block.input)
                tool_results.append({
                    "type":        "tool_result",
                    "tool_use_id": block.id,
                    "content":     json.dumps(output, ensure_ascii=False),
                })
        messages.append({"role": "user", "content": tool_results})
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
목표: 단순 RAG → Claude Agent 전환 + PT Ascendo 실무 특화

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
│   ├── agent.py                     # Claude Agent 실행 루프
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
# Supabase — 프런트(Vite 번들 포함)
VITE_SB_URL=https://xxxx.supabase.co
VITE_SB_KEY=sb_publishable_xxxx     # publishable(=anon) 키 또는 레거시 eyJ... JWT
# Supabase — 서버/수집기 전용 (VITE_ 접두사 금지)
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_SERVICE_KEY=eyJ...         # 수집기 · Edge Function · admin 스크립트

# Claude API (검색·리포트 모두 사용)
ANTHROPIC_API_KEY=sk-ant-...
CLAUDE_MODEL=claude-haiku-4-5-20251001        # RAG 검색 / 레포트 생성
CLAUDE_MODEL_AGENT=claude-sonnet-4-6          # MCP Agent (복잡한 추론)

# Google OAuth (Drive + Gmail 공용)
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
GOOGLE_REDIRECT_URI=http://localhost:5173/oauth/callback

# Notion
NOTION_API_KEY=secret_...
NOTION_DATABASE_IDS=db1_id,db2_id

# BPS WebAPI — 인도네시아 통계청 (물가 CPI · 타이어 수입통계 dataexim)
# 발급: https://webapi.bps.go.id → 가입 → [API KEY] 탭. 사용처: collectors/bps_collector.py(CPI),
#       collectors/bps_import_collector.py(tire_imports), api/search.py POST /collect/tire-imports.
BPS_API_KEY=...

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

## 11. Supabase 연결 · 보안

> 최종 정리: 2026-06-02 (Supabase Auth + RLS `to authenticated` 적용 후). 이전 `AsuraDB_supabase연결.md` 통합.

### 11-1. 작동 흐름 (3단계)

키 값은 **소스코드에 하드코딩되어 있지 않습니다.** 모든 연결 값은 `.env`(§9)에 저장되고 빌드 시점에 Vite가 주입합니다. 따라서 소스 아카이브(zip)에 키가 없는 것이 의도된 설계입니다.

| 단계 | 위치 | 역할 |
|---|---|---|
| ① 실제 값 보관 | `.env` (gitignore, 아카이브 미포함) | 변수명 `VITE_SB_*` (`SUPABASE_*` 아님 — 짧은 이름) |
| ② 값을 읽는 코드 | `src/lib/supabase.ts` | `import.meta.env.VITE_SB_*` 로 로드 |
| ③ 운영 주입 | `npm run deploy` → `gh-pages -d dist` | `.env`를 빌드에 인라인 → GitHub Pages (`base: /asuraDB/`) |

```ts
// src/lib/supabase.ts — 인증 세션 클라이언트 + 동적 토큰 헤더
export const supabase = createClient(SB_URL, SB_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
}); // detectSessionInUrl=false: 해시 라우터 + OAuth 콜백 미사용 충돌 차단

export async function sbHeaders() {            // 로그인 시 사용자 JWT, 아니면 publishable 폴백
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token ?? SB_KEY;
  return { apikey: SB_KEY, Authorization: `Bearer ${token}` };
}
```

> ⚠️ GitHub Pages는 정적 사이트이므로 publishable 키는 **필연적으로 브라우저에 노출**됩니다. 실제 데이터 보호는 RLS + Supabase Auth가 담당합니다(11-3).

### 11-2. 키별 저장 위치

| 키 | 저장 위치 | 노출 | 주의 |
|---|---|---|---|
| **publishable** (`VITE_SB_KEY`) | `.env` → 브라우저 번들 | ⚠️ 노출됨 | RLS+Auth로 보호. service_role 절대 금지. 현재 `sb_publishable_…`(신규 ~46자), 레거시 `eyJ…` JWT anon도 동작 |
| **URL** (`VITE_SB_URL`) | `.env` → 번들 | 노출(정상) | 공개 정보 |
| **service_role** (`SUPABASE_SERVICE_KEY`) | `.env` (`VITE_` 접두사 **금지**) | 서버 전용 | Edge Function · `api/search.py` · 수집기에서만 |

### 11-3. 핵심 보안 원칙

1. **`VITE_` 접두사 변수는 모두 빌드 결과물에 그대로 포함** → 브라우저 노출돼도 되는 값만 지정.
2. **`VITE_SB_KEY`에는 publishable(또는 레거시 anon) 키만.** service_role이 `VITE_`로 노출되면 RLS 우회로 전체 DB가 열림.
3. **데이터 보호는 키가 아니라 RLS + 사용자 JWT가 담당.** RLS가 `to authenticated`로 좁혀져 비로그인(publishable만) 요청은 전 테이블 빈 응답(차단). 로그인 흐름: PIN 입력 → `signInWithPin(pin)` → 계정 매핑(`full@asuradb.local`/`quote@asuradb.local`) → `signInWithPassword` → JWT 발급 → 이후 `sb*` 호출에 자동 첨부.
4. **서비스 키는 클라이언트로 절대 유출 금지.** `SUPABASE_SERVICE_KEY`는 `VITE_` 없는 별도 변수 → 번들 미포함. 사용처: `collectors/*.py`, `scripts/create_auth_users.mjs`, `api/search.py`.

### 11-4. 점검 체크리스트

```
[ 인증 / 키 ]
□ .env 의 VITE_SB_KEY 가 publishable(또는 anon) 키인지 (service_role 아님)
□ SUPABASE_SERVICE_KEY 에 VITE_ 접두사가 없는지
□ dist/assets/*.js 에 sb_secret_ / SERVICE_ROLE 흔적이 없는지
□ 사용 테이블 RLS 활성화 + to authenticated 정책 (enable_rls_all_tables.sql)
□ PIN 로그인 후 Network 탭에서 Authorization: Bearer eyJ…(사용자 JWT) 첨부 확인
□ 비로그인 origin 에서 curl -H "apikey: <publishable>" "$URL/rest/v1/margin_months" → [] (차단) 확인
□ .env 파일 .gitignore 등록
□ Google OAuth redirect_uri 프로덕션 도메인 제한

[ 데이터 수집 ]
□ Gmail: PKDB/ 라벨 메일만 수집 (전체 메일함 접근 금지)
□ 급여/개인정보 포함 문서 수집 제외 필터 적용

[ API ]
□ ANTHROPIC_API_KEY 서버사이드 전용 — 프론트 노출 금지
□ Supabase Edge Function Rate Limit 설정
□ Claude API 비용 모니터링 (Anthropic Console usage)
```

### 11-5. 관련 파일

| 파일 | 역할 |
|---|---|
| `src/lib/supabase.ts` | supabase-js 클라이언트 · 동적 토큰 헤더 · `sb*` fetch 헬퍼 |
| `src/lib/auth.ts` | PIN→계정 매핑 · `signInWithPin` · `signOut` · `syncRoleFromSession` |
| `src/views/PinLogin.vue` | PIN 키패드 UI |
| `src/router/index.ts` | 세션 기반 async 가드 · 역할별 페이지 게이팅 |
| `supabase/migrations/enable_rls_all_tables.sql` | 테이블 RLS 활성화 + `<table>_auth_all` 정책 |
| `scripts/create_auth_users.mjs` | Admin API로 PIN 매핑 계정 생성/갱신 (service_role) |

> PIN 로그인 구현 현황은 §13-1 참조.

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

*AI 엔진: Claude Haiku (`claude-haiku-4-5-20251001`) — RAG 검색/레포트 · Claude Sonnet (`claude-sonnet-4-6`) — MCP Agent*
*Obsidian Vault 연동은 Phase 5 (향후 추가 개발) 예정*

---

## 13. 구현 현황 (2026-05 기준)

### 13-1. PIN 로그인 시스템 (Supabase Auth 연동, 2역할)

| 역할 | PIN | Supabase 계정 (email) | 접속 페이지 | 마진 표시 | 인쇄 출력 | Import/Save |
|------|-----|-------|-----------|---------|---------|------------|
| **관리자** | `0574` | `full@asuradb.local` | 전체 | 정상 | 정상 (Order Info + Margin 포함) | ✓ |
| **고객** | `0000` | `quote@asuradb.local` | 견적서 작성 | 15% 마크업 적용 | Margin 열 숨김 | ✗ |

> 비밀번호는 PIN으로부터 `asuradb-<pin>` 형식으로 유도됨. 실제 비밀(4자리 PIN)은 사용자 입력 → Supabase Auth가 서버 측에서 검증·rate-limit. 계정 생성/갱신은 `scripts/create_auth_users.mjs` (service_role 사용).

**구현 파일**
- `src/views/PinLogin.vue` — PIN 키패드 UI · 에러 메시지 표시 · 비동기 검증 중 입력 잠금
- `src/lib/auth.ts` — `signInWithPin(pin)` → `supabase.auth.signInWithPassword(...)`, `signOut()`, `syncRoleFromSession()`. `Role = 'full' | 'quote'`.
- `src/lib/supabase.ts` — supabase-js 클라이언트 + 세션 토큰 기반 동적 헤더(`sbHeaders`)
- `src/router/index.ts` — 세션 기반 async `beforeEach` 가드. `await supabase.auth.getSession()`로 검사, sessionStorage `asura_auth`로 역할 게이팅 (`role === 'quote'` → `/quote` 강제).
- `src/components/Layout.vue` — 역할별 네비 필터링, 우측 상단 역할 뱃지 (Asura / Customer), 로그아웃 버튼
- `supabase/migrations/enable_rls_all_tables.sql` — 13개 테이블 RLS + `<table>_auth_all` 정책으로 비로그인 차단

---

### 13-2. AI 엔진 구성 (Claude 단일화)

| 작업 | 엔진 | 비고 |
|------|------|------|
| RAG 검색 (`/ai-search`) | Claude Haiku `claude-haiku-4-5-20251001` | `api/search.py` (검색 limit 30) |
| 주간 리포트 생성 | Claude Sonnet `claude-sonnet-4-6` | `generate_monitoring_report.py` |
| MCP Agent (향후) | Claude Sonnet | `mcp/agent.py` |
| 임베딩 생성 | `paraphrase-multilingual-MiniLM-L12-v2` | SentenceTransformer (로컬) |

> 이전에 운영했던 AI 회의록 기능(`Meeting.vue` · `summarize-meeting` Edge Function · `meeting_summaries` 테이블)은 2026-06에 전부 제거됨.

---

### 13-3. 현재 접속 가능 페이지 (라우터 등록 기준)

| 경로 | 페이지 | 접근 가능 역할 |
|------|-------|-------------|
| `/search` | 통합 자료 검색 | 관리자 |
| `/ai-search` | AI 지식 Q&A (Claude Haiku, 최대 30개 문서 컨텍스트) | 관리자 |
| `/quote` | 견적서 작성 (Import/Save는 관리자만) | 관리자, 고객 |
| `/monitor` | KPI 모니터링 | 관리자 |
| `/tire-import` | 인도네시아 타이어 수입량 (BPS EXIM) | 관리자 |
| `/margin` | 마진 분석 (브랜드/제품/고객/SKU 4축) | 관리자 |

> 라우터 가드: 비로그인 → `/login`. 역할이 `quote`인 사용자는 `/quote` 외 경로 접근 시 자동으로 `/quote`로 리다이렉트.
> ※ 자동화 레포트(`/report`)는 라우터에서 제거됨 (백엔드 `/report/generate` 엔드포인트는 유지).

---

### 13-4. KPI 모니터링 (Market KPI Dashboard)

타이어 유통업(PT Ascendo International) 경영 의사결정에 필요한 24개 핵심 지표를
실시간 수집·시각화하고, 주간 모니터링 리포트를 Claude API로 자동 생성하는 기능.

#### 아키텍처

```
[자동 수집]  yfinance → indicator_collector.py (#1 브렌트유, #9~12 환율)
[자동 수집]  웹 스크래핑 → daily_collector.py (#2 천연고무, #3 팜유, #4 니켈)
[자동 수집]  웹 스크래핑 → weekly_collector.py (#5~8 원자재, #13 SCFI)
[자동 수집]  BPS/BI API → monthly_collector.py (#14 BI금리, #15 물가, #16 PMI)
                 │
                 ↓
           indicator_collector.py / daily / weekly / monthly_collector.py
                 │
                 ↓
        Supabase indicator_history
                 │
                 ├────────────────────────────────────────┐
                 ↓                                        ↓
[수동 입력]  Monitor.vue (카드 클릭 → 모달 입력)    generate_monitoring_report.py
                                                          │
                                                    Claude Sonnet API
                                                          │
                                                   monitoring_reports (JSONB)
                                                          │
                                                    Monitor.vue 리포트 패널
```

#### 24개 지표 목록

> ✅ 완전 자동 | 🟡 Proxy/스크립트 지원 | ❌ 수동 입력

| # | ID | 한국명 | 단위 | 알림 주기 | 수집 방식 | Collector |
|---|-----|-------|------|---------|---------|---------|
| 1 | `brent_crude` | 브렌트유 | USD/bbl | 🔴 일일 | ✅ 자동 | `indicator_collector.py` (`BZ=F`) |
| 2 | `nr_rubber` | 천연고무 SICOM | USc/kg | 🔴 일일 | ✅ 자동 | `daily_collector.py` (SICOM → TE) |
| 3 | `cpo` | 팜유 CPO | MYR/MT | 🔴 일일 | ✅ 자동 | `daily_collector.py` (Bursa → TE) |
| 4 | `nickel` | 니켈 | USD/MT | 🔴 일일 | ✅ 자동 | `daily_collector.py` (LME → TE) |
| 5 | `coal` | 석탄 | USD/MT | 🟡 주간 | ✅ 자동 | `weekly_collector.py` (TE Newcastle) |
| 6 | `carbon_black` | 카본블랙 | USD/MT | 🟡 주간 | 🟡 Proxy | `weekly_collector.py` (브렌트유 × 14) |
| 7 | `synthetic_rubber` | 합성고무 BD | USD/MT | 🟡 주간 | ✅ 자동 | `weekly_collector.py` (TE Butadiene) |
| 8 | `steel_wire` | 강선 | USD/MT | 🟡 주간 | ✅ 자동 | `weekly_collector.py` (TE Steel HRC) |
| 9 | `usd_idr` | USD/IDR | IDR | 🔴 일일 | ✅ 자동 | `indicator_collector.py` (`USDIDR=X`) |
| 10 | `usd_krw` | USD/KRW | KRW | 🔴 일일 | ✅ 자동 | `indicator_collector.py` (`USDKRW=X`) |
| 11 | `usd_cny` | USD/CNY | CNY | 🔴 일일 | ✅ 자동 | `indicator_collector.py` (`USDCNY=X`) |
| 12 | `krw_idr` | KRW/IDR | IDR | 🔴 일일 | ✅ 자동 | `indicator_collector.py` (`KRWIDR=X`) |
| 13 | `scfi` | SCFI 컨테이너운임 | Index | 🟡 주간 | ✅ 자동 | `weekly_collector.py` (SSE → MacroMicro) |
| 14 | `bi_rate` | BI 기준금리 | % | 🟢 월간 | ✅ 자동 | `monthly_collector.py` (BI 공식) |
| 15 | `idn_inflation` | 인도네시아 물가 | % | 🟢 월간 | ✅ 자동 | `monthly_collector.py` / `bps_collector.py` |
| 16 | `idn_pmi` | 인도네시아 PMI | Index | 🟢 월간 | ✅ 자동 | `monthly_collector.py` (S&P Global → TE) |
| 17 | `import_tariff` | 수입관세율 | % | 🟢 월간 | ❌ 수동 | — (분기 INSW 조회) |
| 18 | `tbr_sales` | TBR 타이어 판매 | units | 🟡 주간 | ❌ 수동 | — (ERP 미연동) |
| 19 | `otr_sales` | OTR 타이어 판매 | units | 🟡 주간 | ❌ 수동 | — (ERP 미연동) |
| 20 | `ind_sales` | IND 타이어 판매 (산업용) | units | 🟡 주간 | ❌ 수동 | — (ERP 미연동) |
| 21 | `agr_sales` | AGR 타이어 판매 (농경용) | units | 🟡 주간 | ❌ 수동 | — (ERP 미연동) |
| 22 | `competitor_price` | 경쟁사 가격지수 | Index | 🟡 주간 | 🟡 스크립트 | `competitor_sku_list.py` (30개 SKU) |
| 23 | `receivables_ar` | 매출채권 AR | IDR M | 🟡 주간 | ❌ 수동 | — (회계시스템 미연동) |
| 24 | `operating_ratio` | 영업이익률 | % | 🟢 월간 | ❌ 수동 | — (월말 결산 후 입력) |

#### DB 스키마 (3개 테이블)

```sql
-- 지표 정의 마스터 (24개 시드 데이터 포함)
CREATE TABLE market_indicators (
  id          TEXT PRIMARY KEY,             -- 'brent_crude', 'usd_idr' 등
  name_ko     TEXT NOT NULL,
  name_en     TEXT NOT NULL,
  category    TEXT NOT NULL,                -- commodity|fx|freight|policy|market|internal
  alert_level TEXT NOT NULL DEFAULT 'daily',-- daily|weekly|monthly
  unit        TEXT,
  source      TEXT NOT NULL DEFAULT 'manual',-- yfinance|manual
  ticker      TEXT,                         -- yfinance 티커 (자동 수집용)
  sort_order  INT  NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 일별 시계열 값 (indicator_id + recorded_date UNIQUE)
CREATE TABLE indicator_history (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  indicator_id  TEXT NOT NULL REFERENCES market_indicators(id),
  value         NUMERIC,
  recorded_date DATE NOT NULL DEFAULT CURRENT_DATE,
  note          TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (indicator_id, recorded_date)
);

-- 주간 리포트 (Claude 생성 JSONB)
CREATE TABLE monitoring_reports (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_date DATE NOT NULL,
  report_week TEXT,                         -- 'YYYY-WNN' 형식
  content     JSONB NOT NULL DEFAULT '{}',
  raw_markdown TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

#### 관련 파일

| 파일 | 역할 |
|------|------|
| `src/views/Monitor.vue` | KPI 대시보드 페이지 |
| `collectors/indicator_collector.py` | yfinance 자동 수집기 |
| `scripts/generate_monitoring_report.py` | 주간 리포트 Claude 생성기 |
| `supabase/migrations/add_market_monitoring.sql` | 3개 테이블 + 25개 시드 데이터 |

#### 실행 방법

```bash
# 1. DB 마이그레이션 (최초 1회)
supabase db push
# 또는 Supabase Dashboard → SQL Editor에서 직접 실행:
# supabase/migrations/add_market_monitoring.sql

# 2. yfinance 의존성 설치
pip install yfinance

# 3. 자동 수집기 실행 (cron 등록 권장: 매일 오전 9시)
python collectors/indicator_collector.py

# 4. 주간 리포트 생성 (cron 등록 권장: 매주 월요일 오전 8시)
python scripts/generate_monitoring_report.py
```

#### cron 설정 예시 (macOS launchd 또는 crontab)

```cron
# 평일 오전 9시 자동 지표 수집
0 9 * * 1-5 cd /Users/seojonghwan/Desktop/asuraDB && python collectors/indicator_collector.py

# 매주 월요일 오전 8시 주간 리포트 생성
0 8 * * 1   cd /Users/seojonghwan/Desktop/asuraDB && python scripts/generate_monitoring_report.py
```

#### Monitor.vue 주요 기능

| 기능 | 설명 |
|------|------|
| 알림 레벨 탭 | 🔴 일일 / 🟡 주간 / 🟢 월간 / 전체 필터 |
| 카테고리 필터 | 원자재 / 환율 / 물류운임 / 정책거시 / 시장경쟁 / 재무 |
| 지표 카드 | 현재값, 전일 대비 등락률(%), 7일 스파크라인 |
| 수동 입력 모달 | `source = 'manual'` 카드 클릭 → 값 + 메모 입력 후 저장 |
| 주간 리포트 패널 | Executive Summary, 하이라이트, 리스크/기회, 권고사항 표시 |

#### 주간 리포트 JSON 스키마

```json
{
  "executive_summary": "2~3문장 핵심 요약",
  "key_highlights": [
    { "indicator": "브렌트유", "signal": "🔴", "comment": "WTI $82 돌파, 공급 차질 우려" }
  ],
  "category_analysis": {
    "commodity": "원자재 동향 분석 텍스트",
    "fx":        "환율 동향 분석 텍스트",
    "freight":   "물류/운임 동향 분석 텍스트",
    "policy":    "정책/거시경제 분석 텍스트",
    "market":    "시장/경쟁 분석 텍스트",
    "internal":  "재무 분석 텍스트"
  },
  "risks":           ["리스크 항목 1", "리스크 항목 2"],
  "opportunities":   ["기회 항목 1", "기회 항목 2"],
  "recommendations": ["권고사항 1", "권고사항 2", "권고사항 3"]
}
```

---

# 부록 A. React → Vue 3 마이그레이션 노트 (아카이브)

> 마이그레이션 일자: 2026-05-17 — **완료됨**. 원본 `asuradb_current/`(React 18 + TSX + shadcn/ui) → 산출물 `asuradb_vue/`(Vue 3 + SFC).
> 본 부록은 이력·참조용입니다. 이후 작업 계획은 §7 로드맵 / §13 구현현황을 따릅니다. (구 `MIGRATION.md` 통합)

## A-1. 의존성 매핑

| 영역 | React (AS-IS) | Vue (TO-BE) | 비고 |
|------|---------------|-------------|------|
| 프레임워크 | `react@18` + `react-dom` | `vue@3.5` | Composition API + `<script setup>` |
| 빌드 | `@vitejs/plugin-react-swc` | `@vitejs/plugin-vue` | Vite 5 공통 |
| 라우터 | `react-router-dom@6` (HashRouter) | `vue-router@4` (`createWebHashHistory`) | URL 패턴 동일 (`#/`) |
| 상태 | `zustand@5`, lifted `useState` | `pinia@2` (`useUiStore`) | 사이드바 상태 |
| 폼 (예정) | `react-hook-form` + `zod` | `vee-validate` + `zod` | 현재 사용 없음 |
| 데이터 패칭 (예정) | `@tanstack/react-query` | `@tanstack/vue-query` | 향후 Search API 연결 시 |
| UI 기반 | Radix UI + shadcn/ui | `reka-ui`(= Radix Vue) + 자체 shadcn-vue 패턴 | 핵심 6개 컴포넌트만 포팅 |
| 차트 | `recharts@2` | `vue-chartjs@5` + `chart.js@4` | RRF 시각화 컬러 동일 |
| 애니메이션 | `framer-motion@11` | `@vueuse/motion@2` + Vue `<Transition>` | stagger 단순화 |
| 아이콘(범용) | `lucide-react` | `lucide-vue-next` | API 동일 |
| 아이콘(브랜드) | `react-icons/si` | 인라인 SVG (`components/icons/`) | 의존성 감소 |
| 토스트 | `sonner` | `vue-sonner` | API 거의 동일 |
| 유틸 | `clsx` + `tailwind-merge` | 동일 (`cn()` 유지) | |
| 스타일 | TailwindCSS v4 + `tw-animate-css` | 동일 | 디자인 토큰 1:1 보존 |

## A-2. 파일별 매핑

| React (`asuradb_current/`) | Vue (`asuradb_vue/`) | 변경 사항 |
|---------------------------|---------------------|----------|
| `src/main.tsx` | `src/main.ts` | `createApp` + Pinia + Router + MotionPlugin |
| `src/App.tsx` | `src/App.vue` | `HashRouter`/`Toaster` → `reka-ui` `TooltipProvider` + `vue-sonner` |
| `src/index.css` | `src/style.css` | 100% 보존 (디자인 토큰 / `@theme inline` / `@layer base`) |
| `src/components/Layout.tsx` | `src/components/Layout.vue` | `useState`→Pinia / `NavLink`→`RouterLink` / `motion.aside`→CSS transition |
| `src/pages/*.tsx` | `src/views/*.vue` | `useState`→`ref`, `recharts`→`components/charts/`, framer stagger 제거 |
| `src/lib/react-router-dom-proxy.tsx`, `src/lib/motion.ts` | (제거) | React 전용 — 표준 Vue로 대체 |
| `src/components/ui/*` (40+ shadcn) | `ui/{Badge,Button,Input,Separator,card,tooltip}` | **실제 사용 6종만 포팅** |
| `vite.config.ts` (CDN 플러그인) | `vite.config.ts` (단순화) | `cdnPrefixImages()` 제거 — A-4 참조 |

## A-3. 패턴 변환 치트시트

| 패턴 | React | Vue (`<script setup>`) |
|---|---|---|
| State | `const [open,setOpen]=useState(false)` | `const open = ref(false)` |
| 조건부 클래스 | `className={cn('base', a && 'x')}` | `:class="cn('base', a && 'x')"` (동일 `cn()`) |
| 이벤트 | `onClick={fn}` | `@click="fn"` |
| 조건부 렌더 | `{a && <X/>}` / `{a ? <X/> : <Y/>}` | `<X v-if="a"/>` / `<Y v-else/>` |
| 양방향 바인딩 | `value={q} onChange={e=>setQ(e.target.value)}` | `v-model="q"` |
| 애니메이션 | `<motion.div initial animate>` | `<div v-motion :initial :enter>` |
| 라우팅 | `<NavLink to>` / `useNavigate()` / `useLocation()` | `<RouterLink to>` / `useRouter()` / `useRoute()` |

차트 변환: `<AreaChart>`+`<Area>`×4 → `<Line>` `fill:true` ×4 dataset · `<PieChart innerRadius/outerRadius>` → `<Doughnut cutout:'60%'>` · `<ResponsiveContainer>` → wrapper div + `height`(Chart.js는 부모 크기 따름).

## A-4. 디자인 토큰 · 미포팅 · 커스텀 플러그인

- **디자인 토큰**: `src/style.css`의 CSS 변수(`--background`, `--primary`, `--chart-1` …) + `@theme inline` 매핑은 React와 **100% 동일**. 다크 모드는 `<html class="dark">` 강제(동적 토글 미구현 — 필요 시 `@vueuse/core` `useDark()`).
- **미포팅(의도적)**: 미사용 shadcn 40+종(필요 시 `npx shadcn-vue@latest add <x>`), `lovable-tagger`/`cdnPrefixImages()`/`react-router-dom-proxy` 제거, `next-themes`·`embla-carousel-react`·`cmdk` 등 미사용 의존성 제거.
- **`cdnPrefixImages` 복원**: React엔 빌드 시 `/images/**`를 `CDN_IMG_PREFIX`로 재작성하는 Babel 플러그인이 있었음. Vue에서 필요하면 `@vue/compiler-sfc` `parse()`로 `template` src/href/srcset + `style` `url()`을 PostCSS+Vue 트랜스폼 훅으로 분할 처리. 현재 `public/images/**` 자산이 없어 **기본 비활성**.

## A-5. 알려진 차이 / 주의

1. **Stagger 애니메이션** — framer `variants={stagger}` 순차 페이드인은 `@vueuse/motion` 단독 미지원 → 현재 단순 fade-up. 필요 시 `<TransitionGroup>` + 인덱스 기반 `transition-delay`.
2. **Chart tooltip** — Chart.js 기본 tooltip은 Recharts와 색감이 약간 다름(디폴트 어두운 배경 사용).
3. **`asChild`** — React `Slot`은 Vue `as-child`(`reka-ui` 자동 처리). `<RouterLink>` 다중 자식 시 `<RouterLink custom v-slot>` 필요할 수 있음.
4. **Tailwind v4 `@apply` + SFC `<style scoped>`** — 가급적 `class` 인라인 권장(scoped 내 `@apply`는 동작하나 빌드 시간 증가).
