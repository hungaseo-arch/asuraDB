-- Vector 검색 (ivfflat)
CREATE INDEX IF NOT EXISTS idx_doc_embedding ON documents
  USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- Full-Text Search
CREATE INDEX IF NOT EXISTS idx_doc_fts  ON documents USING gin (to_tsvector('simple', content));
CREATE INDEX IF NOT EXISTS idx_doc_trgm ON documents USING gin (content gin_trgm_ops);

-- 필터용
CREATE INDEX IF NOT EXISTS idx_doc_source   ON documents (source);
CREATE INDEX IF NOT EXISTS idx_doc_metadata ON documents USING gin (metadata);
CREATE INDEX IF NOT EXISTS idx_doc_updated  ON documents (updated_at DESC);
