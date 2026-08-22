ALTER TABLE sales ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_company_idempotency_key
    ON sales (company_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;
