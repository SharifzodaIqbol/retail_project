-- +goose Up
-- +goose StatementBegin
ALTER TABLE sales ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_company_idempotency_key
    ON sales (company_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

DROP INDEX IF EXISTS idx_sales_company_idempotency_key;
ALTER TABLE sales DROP COLUMN IF EXISTS idempotency_key;

-- +goose StatementEnd