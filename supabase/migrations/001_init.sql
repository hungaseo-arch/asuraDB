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
