-- +goose Up
-- +goose StatementBegin

-- Таблица магазинов внутри компании
CREATE TABLE IF NOT EXISTS shops (
    id         SERIAL PRIMARY KEY,
    company_id INTEGER NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name       VARCHAR(150) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_shops_company ON shops(company_id);

-- Добавляем shop_id к продавцам (каждый продавец привязан к магазину)
ALTER TABLE users ADD COLUMN IF NOT EXISTS shop_id INTEGER REFERENCES shops(id) ON DELETE SET NULL;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
ALTER TABLE users DROP COLUMN IF EXISTS shop_id;
DROP TABLE IF EXISTS shops;
-- +goose StatementEnd
