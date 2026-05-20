-- ============================================================
-- 검색 성능 최적화 패치
-- Supabase SQL Editor에서 전체 복사-붙여넣기 후 실행
-- ============================================================

-- 1. 새 인덱스 추가 (없으면 생성, 있으면 무시)
CREATE INDEX IF NOT EXISTS idx_doc_title_trgm ON documents
  USING gin (title gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_doc_fts_title ON documents
  USING gin (to_tsvector('simple', COALESCE(title,'') || ' ' || content));

-- 2. hybrid_search 함수 교체 (반환 타입 변경으로 DROP 필요)
DROP FUNCTION IF EXISTS hybrid_search(text, vector, text, text, integer);

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
      to_tsvector('simple', COALESCE(title,'') || ' ' || content)
        @@ plainto_tsquery('simple', query_text)
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
