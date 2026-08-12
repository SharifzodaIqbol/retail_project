-- +goose Up
ALTER TABLE users DROP CONSTRAINT unique_username_per_company;
ALTER TABLE users ADD CONSTRAINT users_username_key UNIQUE (username);

-- +goose Down
ALTER TABLE users DROP CONSTRAINT users_username_key;
ALTER TABLE users ADD CONSTRAINT unique_username_per_company UNIQUE (company_id, username);