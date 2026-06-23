-- +goose Up
ALTER TABLE sale_items ADD COLUMN company_id INTEGER REFERENCES companies(id) ON DELETE CASCADE;
-- +goose Down
ALTER TABLE sale_items DROP COLUMN IF EXISTS company_id;