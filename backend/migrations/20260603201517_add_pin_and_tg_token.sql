-- +goose Up
-- +goose StatementBegin

-- 1. PIN-код для продавцов (4-значный, хранится как хэш bcrypt)
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS pin_hash TEXT;

-- 2. Одноразовый токен для привязки Telegram из приложения (TTL ~10 минут)
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS tg_link_token      VARCHAR(64),
    ADD COLUMN IF NOT EXISTS tg_link_token_at   TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_tg_link_token
    ON users (tg_link_token)
    WHERE tg_link_token IS NOT NULL;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

DROP INDEX IF EXISTS idx_users_tg_link_token;

ALTER TABLE users
    DROP COLUMN IF EXISTS pin_hash,
    DROP COLUMN IF EXISTS tg_link_token,
    DROP COLUMN IF EXISTS tg_link_token_at;

-- +goose StatementEnd
