-- +goose Up
-- +goose StatementBegin

-- Старая колонка quantity уже фактически хранила "учётное" количество в
-- базовых единицах (шт/кг) — переименовываем её в quantity_base, чтобы
-- явно закрепить смысл: это авторитетное число для склада и аналитики.
ALTER TABLE sale_items RENAME COLUMN quantity TO quantity_base;

-- unit_id — какую единицу продажи реально выбрал кассир (для чека).
-- ON DELETE SET NULL: если единицу продажи потом удалят/переименуют,
-- исторический чек не должен ломаться — quantity_base уже посчитан
-- и не зависит от того, жива ли ещё эта единица продажи.
ALTER TABLE sale_items ADD COLUMN IF NOT EXISTS unit_id INTEGER REFERENCES product_units(id) ON DELETE SET NULL;

-- quantity_display — сколько единиц продажи (а не базовых единиц)
-- выбрал кассир: "1 упаковка", "3 блока". Только для красивого чека,
-- никогда не участвует в списании склада или расчёте прибыли.
ALTER TABLE sale_items ADD COLUMN IF NOT EXISTS quantity_display NUMERIC(14, 3);

-- Бэкфилл существующих строк: для старых продаж считаем, что кассир
-- продавал напрямую в базовых единицах (штука/кг), т.е. quantity_display = quantity_base.
UPDATE sale_items SET quantity_display = quantity_base WHERE quantity_display IS NULL;

ALTER TABLE sale_items ALTER COLUMN quantity_display SET NOT NULL;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

ALTER TABLE sale_items DROP COLUMN IF EXISTS quantity_display;
ALTER TABLE sale_items DROP COLUMN IF EXISTS unit_id;
ALTER TABLE sale_items RENAME COLUMN quantity_base TO quantity;

-- +goose StatementEnd
