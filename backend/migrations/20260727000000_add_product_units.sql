-- +goose Up
-- +goose StatementBegin

-- Единица продажи товара. Один товар (products) может продаваться
-- в нескольких единицах (шт, упаковка, блок, коробка...), каждая со
-- своей ценой и своим (опциональным) штрихкодом.
--
-- products.stock остаётся источником истины и всегда в БАЗОВОЙ единице
-- учёта (шт для unit='pcs', кг для unit='kg'). conversion_factor
-- показывает, сколько базовых единиц в одной штуке этой единицы продажи.
-- Для "штуки" (базовой единицы) conversion_factor = 1 всегда, и она
-- создаётся автоматически для каждого товара (ниже бэкфиллом).
CREATE TABLE IF NOT EXISTS product_units (
    id                SERIAL PRIMARY KEY,
    company_id        INTEGER NOT NULL,
    product_id        INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    label             VARCHAR(50) NOT NULL,               -- "шт", "упаковка", "блок", "коробка"...
    conversion_factor NUMERIC(14, 3) NOT NULL CHECK (conversion_factor > 0),
    price             NUMERIC(12, 2) NOT NULL DEFAULT 0,   -- независимая цена, НЕ вычисляется из price_шт
    barcode           VARCHAR(100),                        -- nullable: автогенерация штрихкодов позже
                                                             -- пройдётся по WHERE barcode IS NULL
    is_base           BOOLEAN NOT NULL DEFAULT FALSE,       -- TRUE = это базовая "штучная" единица товара
    is_active         BOOLEAN NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMPTZ DEFAULT NOW()
);

-- Штрихкод уникален в рамках компании (как и у products.barcode), но
-- только когда он реально задан — партиционированный уникальный индекс.
CREATE UNIQUE INDEX IF NOT EXISTS idx_product_units_barcode
    ON product_units(company_id, barcode) WHERE barcode IS NOT NULL;

-- Быстрый доступ "все единицы товара" (самый частый запрос — карточка товара).
CREATE INDEX IF NOT EXISTS idx_product_units_product_id ON product_units(product_id);

-- У товара может быть максимум одна базовая единица.
CREATE UNIQUE INDEX IF NOT EXISTS idx_product_units_one_base
    ON product_units(product_id) WHERE is_base = TRUE;

-- Среди небазовых единиц название (label) уникально в рамках товара —
-- нужно как ON CONFLICT-цель для повторного импорта из Excel (см. ниже),
-- чтобы повторная загрузка того же файла обновляла "упаковку", а не
-- плодила дубликаты.
CREATE UNIQUE INDEX IF NOT EXISTS idx_product_units_label_per_product
    ON product_units(product_id, label) WHERE NOT is_base;

-- Бэкфилл: каждому существующему товару — единица "шт"/"кг" с
-- conversion_factor = 1, ценой = текущей sell_price товара и тем же
-- штрихкодом, что был у товара (чтобы поиск по старым штрихкодам
-- не сломался, пока не переведём чтение целиком на product_units).
INSERT INTO product_units (company_id, product_id, label, conversion_factor, price, barcode, is_base, is_active)
SELECT
    p.company_id,
    p.id,
    CASE WHEN p.unit = 'kg' THEN 'кг' ELSE 'шт' END,
    1,
    p.sell_price,
    p.barcode,
    TRUE,
    p.is_active
FROM products p
WHERE NOT EXISTS (
    SELECT 1 FROM product_units pu WHERE pu.product_id = p.id AND pu.is_base = TRUE
);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

DROP TABLE IF EXISTS product_units;

-- +goose StatementEnd
