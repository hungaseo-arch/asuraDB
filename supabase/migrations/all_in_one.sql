-- 확장 활성화
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- 문서 청크 (Hybrid Search 핵심 테이블)
CREATE TABLE IF NOT EXISTS documents (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  source       TEXT        NOT NULL,
  source_id    TEXT        NOT NULL,
  chunk_index  INT         DEFAULT 0,
  chunk_type   TEXT,
  title        TEXT,
  content      TEXT        NOT NULL,
  content_hash TEXT,
  embedding    VECTOR(384),
  metadata     JSONB       DEFAULT '{}',
  source_url   TEXT,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE (source, source_id, chunk_index)
);

-- 문서 간 링크 관계
CREATE TABLE IF NOT EXISTS document_links (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  from_doc_id  UUID REFERENCES documents(id) ON DELETE CASCADE,
  to_source    TEXT,
  to_source_id TEXT,
  link_type    TEXT,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- 타이어 판매 데이터 (PT Ascendo 특화)
CREATE TABLE IF NOT EXISTS tire_sales (
  id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  branch      TEXT    NOT NULL,
  brand       TEXT    NOT NULL,
  sku         TEXT,
  qty         INTEGER,
  revenue     NUMERIC(15,2),
  margin_pct  NUMERIC(5,2),
  sale_date   DATE    NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
-- Vector 검색 (ivfflat)
CREATE INDEX IF NOT EXISTS idx_doc_embedding ON documents
  USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- Full-Text Search
CREATE INDEX IF NOT EXISTS idx_doc_fts  ON documents USING gin (to_tsvector('simple', content));
CREATE INDEX IF NOT EXISTS idx_doc_trgm ON documents USING gin (content gin_trgm_ops);

-- 필터용
CREATE INDEX IF NOT EXISTS idx_doc_source      ON documents (source);
CREATE INDEX IF NOT EXISTS idx_doc_metadata    ON documents USING gin (metadata);
CREATE INDEX IF NOT EXISTS idx_doc_updated     ON documents (updated_at DESC);
-- 제목 trigram (ILIKE 제목 검색 가속)
CREATE INDEX IF NOT EXISTS idx_doc_title_trgm  ON documents USING gin (title gin_trgm_ops);
-- 제목+본문 합산 FTS (검색 핵심 인덱스)
CREATE INDEX IF NOT EXISTS idx_doc_fts_title   ON documents
  USING gin (to_tsvector('simple', COALESCE(title,'') || ' ' || content));

-- FTS + Vector → RRF (Reciprocal Rank Fusion)
-- 성능 최적화: WHERE에서 full-scan 유발 word_similarity/content ILIKE 제거
--   - FTS는 인덱스(idx_doc_fts_title) 사용
--   - title ILIKE는 idx_doc_title_trgm 사용
--   - word_similarity는 SELECT 스코어링에만 사용 (WHERE 아님)
CREATE OR REPLACE FUNCTION hybrid_search(
  query_text      TEXT,
  query_embedding VECTOR(384),
  source_filter   TEXT    DEFAULT NULL,
  tag_filter      TEXT    DEFAULT NULL,
  match_count     INT     DEFAULT 5
)
RETURNS TABLE(
  id           UUID,
  source       TEXT,
  source_id    TEXT,
  chunk_index  INT,
  chunk_type   TEXT,
  title        TEXT,
  content      TEXT,
  source_url   TEXT,
  metadata     JSONB,
  vector_score FLOAT,
  fts_score    FLOAT,
  rrf_score    FLOAT
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
           ts_rank(
             to_tsvector('simple', COALESCE(title,'') || ' ' || content),
             plainto_tsquery('simple', query_text)
           ) AS score,
           ROW_NUMBER() OVER (
             ORDER BY ts_rank(
               to_tsvector('simple', COALESCE(title,'') || ' ' || content),
               plainto_tsquery('simple', query_text)
             ) DESC
           ) AS rank
    FROM documents
    WHERE (
      -- 인덱스 사용: idx_doc_fts_title (GIN)
      to_tsvector('simple', COALESCE(title,'') || ' ' || content)
        @@ plainto_tsquery('simple', query_text)
      -- 인덱스 사용: idx_doc_title_trgm (GIN) — content ILIKE 제거
      OR title ILIKE '%' || query_text || '%'
    )
      AND (source_filter IS NULL OR source = source_filter)
      AND (tag_filter IS NULL OR metadata->>'tags' ILIKE '%' || tag_filter || '%')
    LIMIT 20
  ),
  rrf AS (
    SELECT COALESCE(v.id, f.id)              AS id,
           COALESCE(v.score, 0)              AS vector_score,
           COALESCE(f.score, 0)              AS fts_score,
           COALESCE(1.0 / (60 + v.rank), 0) +
           COALESCE(1.0 / (60 + f.rank), 0) AS rrf_score
    FROM vector_results v
    FULL OUTER JOIN fts_results f ON v.id = f.id
    ORDER BY rrf_score DESC
    LIMIT match_count
  )
  SELECT d.id, d.source, d.source_id, d.chunk_index, d.chunk_type,
         d.title, d.content, d.source_url, d.metadata,
         r.vector_score, r.fts_score, r.rrf_score
  FROM rrf r
  JOIN documents d ON r.id = d.id
  ORDER BY r.rrf_score DESC;
$$;

-- updated_at 자동 갱신 트리거
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_documents_updated_at ON documents;
CREATE TRIGGER trg_documents_updated_at
  BEFORE UPDATE ON documents
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
