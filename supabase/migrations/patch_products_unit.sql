-- ============================================================
-- products 테이블 스키마 수정
--
-- 변경:
--   type  → item  (컬럼명 변경)
--   추가: wh_price_set (세트 입고가격)
--   추가: unit ('pcs' | 'set')
--   제거: unit_price (판매가격은 견적서 라인에서 결정)
-- ============================================================

-- 컬럼명 변경: type → item
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'products' AND column_name = 'type'
  ) THEN
    ALTER TABLE products RENAME COLUMN type TO item;
  END IF;
END $$;

-- unit_price 제거 (판매가는 견적 라인에서 결정)
ALTER TABLE products DROP COLUMN IF EXISTS unit_price;

-- wh_price_set 추가 (세트 입고가격)
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS wh_price_set NUMERIC(15,2) NOT NULL DEFAULT 0;

-- unit 추가 ('pcs' | 'set') — 제품의 기본 판매 단위
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS unit TEXT NOT NULL DEFAULT 'pcs'
    CHECK (unit IN ('pcs', 'set'));

-- 기존 인덱스 재생성 (type → item)
DROP INDEX IF EXISTS idx_products_type_brand;
CREATE INDEX IF NOT EXISTS idx_products_item_brand ON products(item, brand);

-- 204_quotes.sql이 아직 실행 안 된 경우를 위한 보험:
-- products 테이블이 없으면 새로 생성
CREATE TABLE IF NOT EXISTS products (
  id            UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  item          TEXT,
  brand         TEXT,
  description   TEXT          NOT NULL,
  sku           TEXT          UNIQUE,
  wh_price      NUMERIC(15,2) NOT NULL DEFAULT 0,
  wh_price_set  NUMERIC(15,2) NOT NULL DEFAULT 0,
  unit          TEXT          NOT NULL DEFAULT 'pcs'
                                CHECK (unit IN ('pcs', 'set')),
  currency      TEXT          NOT NULL DEFAULT 'USD',
  is_active     BOOLEAN       NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
