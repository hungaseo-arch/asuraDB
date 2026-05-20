-- ============================================================
-- 견적서 저장/불러오기 스키마 확정판
-- quotes, quote_items 테이블 생성 (없으면) + 컬럼 추가
-- ============================================================

-- ── quotes 테이블 ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS quotes (
  id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_number        TEXT          UNIQUE NOT NULL,
  customer_name       TEXT,
  customer_po         TEXT,
  sales_rep           TEXT,
  warehouse           TEXT,
  delivery_date       DATE,
  delivery_method     TEXT,
  payment_terms       TEXT,
  notes               TEXT,
  additional_discount NUMERIC(5,2)  NOT NULL DEFAULT 0,
  ppn_rate            NUMERIC(5,2)  NOT NULL DEFAULT 11,
  status              TEXT          NOT NULL DEFAULT 'draft'
                        CHECK (status IN ('draft','sent','approved','cancelled')),
  currency            TEXT          NOT NULL DEFAULT 'USD',
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- 기존 테이블에 없을 수 있는 컬럼 추가
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS customer_po    TEXT;
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS delivery_date  DATE;

-- ── quote_items 테이블 ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS quote_items (
  id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_id    UUID          NOT NULL REFERENCES quotes(id) ON DELETE CASCADE,
  line_no     INTEGER       NOT NULL,
  product_id  UUID          REFERENCES products(id) ON DELETE SET NULL,
  type        TEXT,
  brand       TEXT,
  description TEXT,
  qty         NUMERIC(15,3) NOT NULL DEFAULT 0,
  unit        TEXT          NOT NULL DEFAULT 'pcs' CHECK (unit IN ('pcs','set')),
  wh_price    NUMERIC(15,2) NOT NULL DEFAULT 0,
  unit_price  NUMERIC(15,2) NOT NULL DEFAULT 0,
  discount    NUMERIC(5,2)  NOT NULL DEFAULT 0
                CHECK (discount >= 0 AND discount <= 100),
  net_price   NUMERIC(15,2) GENERATED ALWAYS AS (
                ROUND(unit_price * (1 - discount / 100.0), 2)
              ) STORED,
  amount      NUMERIC(15,2) GENERATED ALWAYS AS (
                ROUND(qty * ROUND(unit_price * (1 - discount / 100.0), 2), 2)
              ) STORED,
  margin      NUMERIC(10,6) GENERATED ALWAYS AS (
                CASE WHEN wh_price = 0 THEN NULL
                ELSE ROUND(
                  (ROUND(unit_price * (1 - discount / 100.0), 2) - wh_price) / wh_price, 6)
                END
              ) STORED,
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (quote_id, line_no)
);

ALTER TABLE quote_items ADD COLUMN IF NOT EXISTS unit TEXT NOT NULL DEFAULT 'pcs';

-- ── 인덱스 ───────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_quotes_created  ON quotes(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_quotes_status   ON quotes(status);
CREATE INDEX IF NOT EXISTS idx_qi_quote        ON quote_items(quote_id);

-- ── updated_at 트리거 ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS trg_quotes_updated_at ON quotes;
CREATE TRIGGER trg_quotes_updated_at
  BEFORE UPDATE ON quotes
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ── 채번 함수 ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION next_quote_number()
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
  yr  TEXT := TO_CHAR(NOW(), 'YYYY');
  seq INT;
BEGIN
  SELECT COUNT(*) + 1 INTO seq FROM quotes WHERE quote_number LIKE 'SO-' || yr || '-%';
  RETURN 'SO-' || yr || '-' || LPAD(seq::TEXT, 4, '0');
END;
$$;
