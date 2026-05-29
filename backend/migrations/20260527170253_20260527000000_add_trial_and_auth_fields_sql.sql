-- +goose Up
-- +goose StatementBegin

-- 1. Расширяем таблицу companies
ALTER TABLE companies ADD COLUMN IF NOT EXISTS owner_phone VARCHAR(20) UNIQUE;
ALTER TABLE companies ADD COLUMN IF NOT EXISTS is_phone_verified BOOLEAN DEFAULT false;

-- 2. Отдельная таблица для device fingerprints
CREATE TABLE IF NOT EXISTS trial_devices (
    id            SERIAL PRIMARY KEY,
    device_id     VARCHAR(255) NOT NULL,
    company_id    INT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    registered_at TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT uq_device UNIQUE (device_id)
);

CREATE INDEX IF NOT EXISTS idx_trial_devices_device_id ON trial_devices(device_id);

-- 3. Таблица для SMS-кодов (уровень 2)
CREATE TABLE IF NOT EXISTS phone_verifications (
    id          SERIAL PRIMARY KEY,
    phone       VARCHAR(20) NOT NULL,
    code        VARCHAR(6)  NOT NULL,
    attempts    INT         DEFAULT 0,
    expires_at  TIMESTAMPTZ NOT NULL,
    used        BOOLEAN     DEFAULT false,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_phone_verifications_phone ON phone_verifications(phone);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

-- Удаляем индексы и таблицы в обратном порядке
DROP INDEX IF EXISTS idx_phone_verifications_phone;
DROP TABLE IF EXISTS phone_verifications;

DROP INDEX IF EXISTS idx_trial_devices_device_id;
DROP TABLE IF EXISTS trial_devices;

-- Удаляем добавленные колонки из таблицы companies
ALTER TABLE companies DROP COLUMN IF EXISTS is_phone_verified;
ALTER TABLE companies DROP COLUMN IF EXISTS owner_phone;

-- +goose StatementEnd