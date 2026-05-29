-- +goose Up
-- +goose StatementBegin

-- ─────────────────────────────────────────────────────────────
-- 1. Добавляем колонку language в таблицу users
--    'tj' = таджикский (по умолчанию), 'ru' = русский
-- ─────────────────────────────────────────────────────────────
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS language VARCHAR(5) NOT NULL DEFAULT 'tj';

-- ─────────────────────────────────────────────────────────────
-- 2. Таблица должников
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS debtors (
    id          SERIAL PRIMARY KEY,
    company_id  INTEGER      NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    full_name   VARCHAR(150) NOT NULL,
    phone       VARCHAR(30),
    total_debt  NUMERIC(12, 2) NOT NULL DEFAULT 0.00,  -- текущий итоговый долг
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_debtors_company ON debtors(company_id);

-- ─────────────────────────────────────────────────────────────
-- 3. История операций по каждому должнику
--    type: 'take' — взял в долг, 'pay' — вернул долг
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS debt_history (
    id         SERIAL PRIMARY KEY,
    debtor_id  INTEGER      NOT NULL REFERENCES debtors(id) ON DELETE CASCADE,
    amount     NUMERIC(12, 2) NOT NULL,
    type       VARCHAR(4)   NOT NULL CHECK (type IN ('take', 'pay')),
    note       TEXT,                                   -- необязательный комментарий
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_debt_history_debtor ON debt_history(debtor_id);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE IF EXISTS debt_history;
DROP TABLE IF EXISTS debtors;
ALTER TABLE users DROP COLUMN IF EXISTS language;
-- +goose StatementEnd