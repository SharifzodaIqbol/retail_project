-- +goose Up
ALTER TABLE sale_items ADD COLUMN IF NOT EXISTS buy_price_at_sale NUMERIC(12, 2);
UPDATE sale_items si
SET buy_price_at_sale = p.buy_price
FROM products p
WHERE si.product_id = p.id AND si.buy_price_at_sale IS NULL;
UPDATE sale_items SET buy_price_at_sale = 0 WHERE buy_price_at_sale IS NULL;
 
ALTER TABLE sale_items ALTER COLUMN buy_price_at_sale SET NOT NULL;
ALTER TABLE sale_items ALTER COLUMN buy_price_at_sale SET DEFAULT 0;

-- +goose Down
SELECT 'down SQL query';
ALTER TABLE sale_items DROP COLUMN IF EXISTS buy_price_at_sale;