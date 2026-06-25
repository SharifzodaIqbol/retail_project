-- +goose Up
-- +goose StatementBegin

-- Единица измерения товара: 'pcs' (шт) или 'kg' (кг).
ALTER TABLE products ADD COLUMN IF NOT EXISTS unit VARCHAR(10) NOT NULL DEFAULT 'pcs';
ALTER TABLE products ADD CONSTRAINT chk_products_unit CHECK (unit IN ('pcs', 'kg'));

-- Остаток должен поддерживать дробные значения для товаров на вес (кг),
-- поэтому переводим stock из INTEGER в NUMERIC.
ALTER TABLE products ALTER COLUMN stock TYPE NUMERIC(14, 3) USING stock::numeric;
ALTER TABLE products ALTER COLUMN stock SET DEFAULT 0;


-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

ALTER TABLE products ALTER COLUMN stock TYPE INTEGER USING ROUND(stock)::integer;
ALTER TABLE products DROP CONSTRAINT IF EXISTS chk_products_unit;
ALTER TABLE products DROP COLUMN IF EXISTS unit;

-- +goose StatementEnd
