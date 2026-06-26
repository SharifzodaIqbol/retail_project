-- +goose Up
ALTER TABLE users
ADD COLUMN IF NOT EXISTS tg_link_token_expires_at TIMESTAMPTZ;

-- +goose Down
ALTER TABLE users
DROP COLUMN IF EXISTS tg_link_token_expires_at;

