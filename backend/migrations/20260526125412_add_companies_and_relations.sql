-- +goose Up
-- 1. Создаем таблицу компаний (бизнесов)
CREATE TABLE IF NOT EXISTS companies (
    id             SERIAL PRIMARY KEY,
    name           VARCHAR(255) NOT NULL,
    billing_plan   VARCHAR(50) NOT NULL DEFAULT 'trial',
    trial_ends_at  TIMESTAMPTZ NOT NULL,
    is_paid        BOOLEAN NOT NULL DEFAULT FALSE,
    created_at     TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Привязываем пользователей к компании
ALTER TABLE users ADD COLUMN company_id INTEGER REFERENCES companies(id) ON DELETE CASCADE;

-- 3. Привязываем товары к компании
ALTER TABLE products ADD COLUMN company_id INTEGER REFERENCES companies(id) ON DELETE CASCADE;

-- Переделываем уникальность штрихкода
ALTER TABLE products DROP CONSTRAINT IF EXISTS products_barcode_key;
ALTER TABLE products ADD CONSTRAINT unique_barcode_per_company UNIQUE (company_id, barcode);

-- +goose Down
-- Шаги в обратном порядке для отката изменений
ALTER TABLE products DROP CONSTRAINT IF EXISTS unique_barcode_per_company;
-- Если старый констреинт уникальности barcode существовал, по-хорошему его нужно вернуть:
-- ALTER TABLE products ADD CONSTRAINT products_barcode_key UNIQUE (barcode);

ALTER TABLE products DROP COLUMN IF EXISTS company_id;
ALTER TABLE users DROP COLUMN IF EXISTS company_id;
DROP TABLE IF EXISTS companies;