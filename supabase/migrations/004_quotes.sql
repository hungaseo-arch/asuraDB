-- ============================================================
-- 견적서 (Quote / Sales Order) 스키마
-- ============================================================

-- ── 1. 제품 마스터 ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS products (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  type        TEXT,                               -- 제품 유형 (AGR, OTR, TBR, Rubbertrack …)
  brand       TEXT,
  description TEXT        NOT NULL,
  sku         TEXT        UNIQUE,
  wh_price    NUMERIC(15,2) NOT NULL DEFAULT 0,  -- 입고가격
  unit_price  NUMERIC(15,2) NOT NULL DEFAULT 0,  -- 기본 판매가격
  currency    TEXT        NOT NULL DEFAULT 'USD',
  is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── 2. 견적 헤더 ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS quotes (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_number        TEXT        UNIQUE NOT NULL,  -- SO-2026-001 형식
  sales_rep           TEXT,
  warehouse           TEXT,
  delivery_method     TEXT,
  payment_terms       TEXT,
  customer_name       TEXT,
  customer_address    TEXT,
  validity_date       DATE,
  currency            TEXT        NOT NULL DEFAULT 'USD',
  additional_discount NUMERIC(5,2) NOT NULL DEFAULT 0,  -- 추가 할인 %
  ppn_rate            NUMERIC(5,2) NOT NULL DEFAULT 11, -- PPN (부가세) %
  truncation          NUMERIC(15,2) NOT NULL DEFAULT 0, -- 절사 금액 (음수 저장)
  status              TEXT        NOT NULL DEFAULT 'draft'
                        CHECK (status IN ('draft','sent','approved','cancelled')),
  notes               TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── 3. 견적 라인 아이템 ─────────────────────────────────────
-- net_price  = unit_price × (1 - discount / 100)          -- 할인 후 최종 판매가격 (단가)
-- amount     = qty × net_price                             -- 라인 합계
-- margin     = (net_price - wh_price) / wh_price           -- 마진율
CREATE TABLE IF NOT EXISTS quote_items (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_id    UUID        NOT NULL REFERENCES quotes(id) ON DELETE CASCADE,
  line_no     INTEGER     NOT NULL,               -- 순번 (1부터)
  product_id  UUID        REFERENCES products(id) ON DELETE SET NULL,

  -- 입력값 (snapshot: 저장 시점 가격 고정)
  type        TEXT,
  brand       TEXT,
  description TEXT,
  qty         NUMERIC(15,3) NOT NULL DEFAULT 0,
  wh_price    NUMERIC(15,2) NOT NULL DEFAULT 0,   -- 입고가격
  unit_price  NUMERIC(15,2) NOT NULL DEFAULT 0,   -- 판매가격
  discount    NUMERIC(5,2)  NOT NULL DEFAULT 0    -- 할인율 %
                CHECK (discount >= 0 AND discount <= 100),

  -- 계산값 (GENERATED STORED)
  net_price   NUMERIC(15,2) GENERATED ALWAYS AS (
                ROUND(unit_price * (1 - discount / 100.0), 2)
              ) STORED,

  amount      NUMERIC(15,2) GENERATED ALWAYS AS (
                ROUND(qty * ROUND(unit_price * (1 - discount / 100.0), 2), 2)
              ) STORED,

  -- margin = (net_price - wh_price) / wh_price
  -- wh_price = 0 이면 NULL 처리
  margin      NUMERIC(10,6) GENERATED ALWAYS AS (
                CASE
                  WHEN wh_price = 0 THEN NULL
                  ELSE ROUND(
                    (ROUND(unit_price * (1 - discount / 100.0), 2) - wh_price)
                    / wh_price,
                    6
                  )
                END
              ) STORED,

  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (quote_id, line_no)
);

-- ── 4. 인덱스 ───────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_products_sku         ON products(sku);
CREATE INDEX IF NOT EXISTS idx_products_type_brand  ON products(type, brand);
CREATE INDEX IF NOT EXISTS idx_products_active      ON products(is_active) WHERE is_active = TRUE;

CREATE INDEX IF NOT EXISTS idx_quotes_number        ON quotes(quote_number);
CREATE INDEX IF NOT EXISTS idx_quotes_status        ON quotes(status);
CREATE INDEX IF NOT EXISTS idx_quotes_created       ON quotes(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_quote_items_quote    ON quote_items(quote_id);
CREATE INDEX IF NOT EXISTS idx_quote_items_product  ON quote_items(product_id) WHERE product_id IS NOT NULL;

-- ── 5. updated_at 자동 갱신 트리거 ─────────────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_products_updated_at
  BEFORE UPDATE ON products
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE TRIGGER trg_quotes_updated_at
  BEFORE UPDATE ON quotes
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ── 6. quote_number 자동 채번 함수 ─────────────────────────
-- 호출: SELECT next_quote_number();  → 'SO-2026-0001'
CREATE OR REPLACE FUNCTION next_quote_number()
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
  yr   TEXT := TO_CHAR(NOW(), 'YYYY');
  seq  INT;
BEGIN
  SELECT COUNT(*) + 1
    INTO seq
    FROM quotes
   WHERE quote_number LIKE 'SO-' || yr || '-%';

  RETURN 'SO-' || yr || '-' || LPAD(seq::TEXT, 4, '0');
END;
$$;

-- ── 7. 견적 요약 뷰 ─────────────────────────────────────────
-- sub_total         : 라인 합계 (추가 할인 전)
-- additional_disc_amt: 추가 할인 금액
-- taxable_amount    : 과세 기준 금액
-- ppn_amount        : PPN 금액
-- total             : 최종 합계
CREATE OR REPLACE VIEW quote_summary AS
SELECT
  q.id,
  q.quote_number,
  q.sales_rep,
  q.customer_name,
  q.status,
  q.currency,
  q.additional_discount,
  q.ppn_rate,
  q.truncation,
  q.created_at,

  COALESCE(SUM(qi.amount), 0)                                               AS sub_total,

  ROUND(COALESCE(SUM(qi.amount), 0) * q.additional_discount / 100.0, 2)    AS additional_disc_amt,

  ROUND(
    COALESCE(SUM(qi.amount), 0)
    * (1 - q.additional_discount / 100.0),
    2
  )                                                                          AS after_disc_amount,

  ROUND(
    COALESCE(SUM(qi.amount), 0)
    * (1 - q.additional_discount / 100.0)
    * q.ppn_rate / 100.0,
    2
  )                                                                          AS ppn_amount,

  ROUND(
    COALESCE(SUM(qi.amount), 0)
    * (1 - q.additional_discount / 100.0)
    * (1 + q.ppn_rate / 100.0)
    + q.truncation,
    2
  )                                                                          AS total

FROM quotes q
LEFT JOIN quote_items qi ON qi.quote_id = q.id
GROUP BY q.id;
