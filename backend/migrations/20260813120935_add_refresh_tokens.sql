-- +goose Up
-- Refresh-токены: позволяют выдавать пользователю новый (короткоживущий)
-- JWT без повторного ввода логина/пароля/PIN, пока refresh-токен не
-- истёк или не был отозван. Храним не сам токен, а его SHA-256 хэш —
-- если БД когда-нибудь утечёт, токенами нельзя будет воспользоваться
-- напрямую (аналогично тому, как хранится password_hash/pin_hash).
CREATE TABLE refresh_tokens (
    id          BIGSERIAL PRIMARY KEY,
    user_id     INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash  TEXT NOT NULL,
    device_id   TEXT,
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX refresh_tokens_token_hash_uidx ON refresh_tokens (token_hash);
CREATE INDEX refresh_tokens_user_id_idx ON refresh_tokens (user_id);

-- +goose Down
DROP TABLE IF EXISTS refresh_tokens;