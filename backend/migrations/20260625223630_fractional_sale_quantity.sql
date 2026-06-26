-- +goose Up
-- +goose StatementBegin

-- Позволяет продавать товары на вес (кг) дробными количествами, например 0.5 кг.
ALTER TABLE sale_items ALTER COLUMN quantity TYPE NUMERIC(12, 3) USING quantity::numeric;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

ALTER TABLE sale_items ALTER COLUMN quantity TYPE INTEGER USING ROUND(quantity)::integer;

-- +goose StatementEnd
