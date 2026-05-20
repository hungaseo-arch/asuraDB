-- ============================================================
-- 소스 다양성 보장 패치 v2 (성능 최적화 포함)
--
-- v1 문제: PARTITION BY source를 LIMIT 없이 적용 → 풀 스캔 발생
-- v2 수정: 1단계 인덱스로 상위 60개 추출 → 2단계 60개 내에서 소스 분배
--          ivfflat / GIN 인덱스 정상 사용 유지
-- ============================================================

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
  WITH
  -- 1단계: ivfflat 인덱스로 전체 상위 60개 추출 (빠름)
  vector_top AS (
    SELECT id,
           source,
           1 - (embedding <=> query_embedding) AS score
    FROM documents
    WHERE (source_filter IS NULL OR source = source_filter)
      AND (tag_filter IS NULL OR metadata->>'tags' ILIKE '%' || tag_filter || '%')
    ORDER BY embedding <=> query_embedding
    LIMIT 60
  ),
  -- 2단계: 60개 내에서 전체 상위 10개 + 소스별 상위 3개 선별 (60행 대상, 빠름)
  vector_ranked AS (
    SELECT id,
           score,
           ROW_NUMBER() OVER (ORDER BY score DESC)                   AS global_rank,
           ROW_NUMBER() OVER (PARTITION BY source ORDER BY score DESC) AS source_rank
    FROM vector_top
  ),
  vector_results AS (
    SELECT id, score,
           ROW_NUMBER() OVER (ORDER BY score DESC) AS rank
    FROM vector_ranked
    WHERE global_rank <= 10 OR source_rank <= 3
  ),
  -- FTS: GIN 인덱스로 상위 60개 추출 후 소스 분배
  fts_top AS (
    SELECT id,
           source,
           ts_rank(
             to_tsvector('simple', COALESCE(title,'') || ' ' || content),
             plainto_tsquery('simple', query_text)
           ) AS score
    FROM documents
    WHERE (
      to_tsvector('simple', COALESCE(title,'') || ' ' || content)
        @@ plainto_tsquery('simple', query_text)
      OR title ILIKE '%' || query_text || '%'
    )
      AND (source_filter IS NULL OR source = source_filter)
      AND (tag_filter IS NULL OR metadata->>'tags' ILIKE '%' || tag_filter || '%')
    ORDER BY score DESC
    LIMIT 60
  ),
  fts_ranked AS (
    SELECT id,
           score,
           ROW_NUMBER() OVER (ORDER BY score DESC)                   AS global_rank,
           ROW_NUMBER() OVER (PARTITION BY source ORDER BY score DESC) AS source_rank
    FROM fts_top
  ),
  fts_results AS (
    SELECT id, score,
           ROW_NUMBER() OVER (ORDER BY score DESC) AS rank
    FROM fts_ranked
    WHERE global_rank <= 10 OR source_rank <= 3
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
