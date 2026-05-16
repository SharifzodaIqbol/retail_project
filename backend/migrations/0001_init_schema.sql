-- +goose Up
-- ═══════════════════════════════════════════════════════════
-- Retail Management System — Schema v2
-- ═══════════════════════════════════════════════════════════

-- Пользователи
CREATE TABLE IF NOT EXISTS users (
    id            SERIAL PRIMARY KEY,
    username      VARCHAR(100) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role          VARCHAR(20) NOT NULL DEFAULT 'seller', -- 'owner' | 'seller'
    tg_chat_id    BIGINT,
    created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- Товары
CREATE TABLE IF NOT EXISTS products (
    id         SERIAL PRIMARY KEY,
    name       VARCHAR(255) NOT NULL,
    barcode    VARCHAR(100) UNIQUE NOT NULL,
    buy_price  NUMERIC(12, 2) NOT NULL DEFAULT 0,
    sell_price NUMERIC(12, 2) NOT NULL DEFAULT 0,
    stock      INTEGER NOT NULL DEFAULT 0,
    is_active  BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Индексы для быстрого поиска товаров
CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode);
CREATE INDEX IF NOT EXISTS idx_products_name    ON products USING gin(to_tsvector('russian', name));

-- Продажи
CREATE TABLE IF NOT EXISTS sales (
    id            SERIAL PRIMARY KEY,
    seller_id     INTEGER REFERENCES users(id) ON DELETE SET NULL,
    total_amount  NUMERIC(12, 2) NOT NULL,
    is_canceled   BOOLEAN NOT NULL DEFAULT FALSE,
    cancel_reason TEXT,
    created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sales_created_at ON sales(created_at);
CREATE INDEX IF NOT EXISTS idx_sales_seller_id  ON sales(seller_id);

-- Позиции чека
CREATE TABLE IF NOT EXISTS sale_items (
    id            SERIAL PRIMARY KEY,
    sale_id       INTEGER NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
    product_id    INTEGER NOT NULL REFERENCES products(id),
    quantity      INTEGER NOT NULL,
    price_at_sale NUMERIC(12, 2) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id    ON sale_items(sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_product_id ON sale_items(product_id);


-- +goose Down
DROP TABLE IF EXISTS sale_items;
DROP TABLE IF EXISTS sales;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS users;