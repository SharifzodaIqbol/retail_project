-- +goose Up
-- +goose StatementBegin

-- 1. Удаляем старый глобальный констреинт уникальности на колонку username
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_username_key;

-- 2. Добавляем новый составной констреинт: имя уникально только внутри одной компании
ALTER TABLE users ADD CONSTRAINT unique_username_per_company UNIQUE (company_id, username);

-- +goose StatementEnd


-- +goose Down
-- +goose StatementBegin

-- 1. Удаляем составной констреинт
ALTER TABLE users DROP CONSTRAINT IF EXISTS unique_username_per_company;

-- 2. Возвращаем старую глобальную уникальность для username (как было изначально)
ALTER TABLE users ADD CONSTRAINT users_username_key UNIQUE (username);

-- +goose StatementEnd