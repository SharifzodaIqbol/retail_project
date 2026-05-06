-- +goose Up
-- Таблица пользователей (продавцы и хозяин)
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role VARCHAR(20) DEFAULT 'seller', -- 'admin' (хозяин) или 'seller' (продавец)
    tg_chat_id BIGINT,                -- ID чата в телеграм для уведомлений
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Таблица товаров
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    barcode VARCHAR(100) UNIQUE,      -- Для сканера штрихкодов
    buy_price DECIMAL(12, 2) NOT NULL, -- Цена закупки (для расчета прибыли)
    sell_price DECIMAL(12, 2) NOT NULL, -- Цена продажи
    stock INT NOT NULL DEFAULT 0,      -- Остаток на складе
    is_active BOOLEAN DEFAULT TRUE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Таблица чеков (продаж)
CREATE TABLE sales (
    id SERIAL PRIMARY KEY,
    seller_id INT REFERENCES users(id),
    total_amount DECIMAL(12, 2) NOT NULL,
    is_canceled BOOLEAN DEFAULT FALSE, -- Флаг отмены
    cancel_reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Состав чека (какие именно товары купили)
CREATE TABLE sale_items (
    id SERIAL PRIMARY KEY,
    sale_id INT REFERENCES sales(id) ON DELETE CASCADE,
    product_id INT REFERENCES products(id),
    quantity INT NOT NULL,
    price_at_sale DECIMAL(12, 2) NOT NULL -- Фиксируем цену на момент продажи
);

-- +goose Down
DROP TABLE sale_items;
DROP TABLE sales;
DROP TABLE products;
DROP TABLE users;