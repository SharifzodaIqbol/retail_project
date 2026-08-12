-- +goose Up
CREATE UNIQUE INDEX users_username_lower_uidx ON users (LOWER(username));

-- +goose Down
DROP INDEX IF EXISTS users_username_lower_uidx;