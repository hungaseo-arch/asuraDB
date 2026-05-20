-- ============================================================
-- 관련도 임계값 패치
--
-- 문제: vector 검색에 최소 점수 없어 관련 없는 문서가 포함됨
-- 수정: vector_score >= 0.35 미만 문서 제외
--       source 다양성은 threshold 통과한 것만 적용
-- ============================================================

DROP FUNCTION IF EXISTS hybrid_search(text, vector, text, text, integer);

CREATE OR REPLACE FUNCTION hybrid_search(
  query_text      TEXT,
  query_embedding VECTOR(384),
  source_filter   TEXT    DEFAULT NULL,
  tag_filter      TEXT    DEFAULT NULL,
  match_count     INT     DEFAULT 10
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
  -- 1단계: ivfflat 인덱스로 상위 60개 추출
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
  -- 2단계: 임계값(0.35) 통과한 문서만 → 전체 상위 10개 + 소스별 상위 3개
  vector_ranked AS (
    SELECT id,
           score,
           ROW_NUMBER() OVER (ORDER BY score DESC)                     AS global_rank,
           ROW_NUMBER() OVER (PARTITION BY source ORDER BY score DESC) AS source_rank
    FROM vector_top
    WHERE score >= 0.35   -- 관련도 임계값: 코사인 유사도 0.35 미만 제외
  ),
  vector_results AS (
    SELECT id, score,
           ROW_NUMBER() OVER (ORDER BY score DESC) AS rank
    FROM vector_ranked
    WHERE global_rank <= 10 OR source_rank <= 3
  ),
  -- FTS: 키워드 일치 문서 (임계값 불필요 — 키워드 매칭 자체가 필터)
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
           ROW_NUMBER() OVER (ORDER BY score DESC)                     AS global_rank,
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
