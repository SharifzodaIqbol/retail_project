-- +goose Up
SELECT 'up SQL query';
ALTER TABLE products ALTER COLUMN barcode DROP NOT NULL;
-- +goose Down
SELECT 'down SQL query';
ALTER TABLE products ALTER COLUMN barcode SET NOT NULL;