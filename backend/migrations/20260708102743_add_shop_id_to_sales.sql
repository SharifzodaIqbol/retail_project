-- +goose Up
-- +goose StatementBegin

-- Многомагазинная аналитика: продажа теперь привязывается к конкретному
-- магазину (shops), а не только к компании. Это позволяет владельцу
-- переключаться между магазинами и видеть прибыль/выручку каждого из них
-- отдельно, а также сравнивать их между собой.
--
-- shop_id проставляется в момент продажи из shop_id продавца (см.
-- ExecuteSale), поэтому колонка nullable: у продавца может не быть
-- назначенного магазина (тогда чек попадает в "без магазина").

ALTER TABLE sales ADD COLUMN IF NOT EXISTS shop_id INTEGER REFERENCES shops(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_sales_shop_id ON sales(shop_id);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
ALTER TABLE sales DROP COLUMN IF EXISTS shop_id;
-- +goose StatementEnd
