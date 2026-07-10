-- +goose Up
-- +goose StatementBegin

-- Магазин, который сейчас "открыт" у владельца в приложении (для владельцев,
-- у которых несколько магазинов). У продавца текущий магазин = users.shop_id
-- (задаётся один раз при создании сотрудника и не переключается).
ALTER TABLE users ADD COLUMN IF NOT EXISTS current_shop_id INTEGER REFERENCES shops(id) ON DELETE SET NULL;

-- Привязка данных к конкретному магазину внутри компании.
ALTER TABLE products ADD COLUMN IF NOT EXISTS shop_id INTEGER REFERENCES shops(id) ON DELETE SET NULL;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS shop_id INTEGER REFERENCES shops(id) ON DELETE SET NULL;
ALTER TABLE debtors ADD COLUMN IF NOT EXISTS shop_id INTEGER REFERENCES shops(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_products_shop ON products(shop_id);
CREATE INDEX IF NOT EXISTS idx_sales_shop ON sales(shop_id);
CREATE INDEX IF NOT EXISTS idx_debtors_shop ON debtors(shop_id);

-- Бэкфилл: у компаний, где уже были данные, но ещё нет ни одного магазина —
-- создаём магазин "Мағозаи асосӣ" ("Основной магазин") и переносим туда
-- все существующие товары/продажи/долги/сотрудников, чтобы после апдейта
-- ничего не "потерялось из вида" у владельца.
DO $$
DECLARE
    comp RECORD;
    new_shop_id INTEGER;
BEGIN
    FOR comp IN
        SELECT c.id AS company_id
        FROM companies c
        WHERE NOT EXISTS (SELECT 1 FROM shops s WHERE s.company_id = c.id)
    LOOP
        INSERT INTO shops (company_id, name) VALUES (comp.company_id, 'Мағозаи асосӣ')
        RETURNING id INTO new_shop_id;

        UPDATE products SET shop_id = new_shop_id WHERE company_id = comp.company_id AND shop_id IS NULL;
        UPDATE sales SET shop_id = new_shop_id WHERE company_id = comp.company_id AND shop_id IS NULL;
        UPDATE debtors SET shop_id = new_shop_id WHERE company_id = comp.company_id AND shop_id IS NULL;
        UPDATE users SET shop_id = COALESCE(shop_id, new_shop_id), current_shop_id = new_shop_id
            WHERE company_id = comp.company_id;
    END LOOP;
END $$;

-- Штрихкод должен быть уникален в рамках магазина, а не всей компании —
-- два разных магазина одной компании могут независимо использовать один
-- и тот же штрихкод для разных товаров.
ALTER TABLE products DROP CONSTRAINT IF EXISTS unique_barcode_per_company;
ALTER TABLE products ADD CONSTRAINT unique_barcode_per_shop UNIQUE (company_id, shop_id, barcode);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
ALTER TABLE products DROP CONSTRAINT IF EXISTS unique_barcode_per_shop;
ALTER TABLE products ADD CONSTRAINT unique_barcode_per_company UNIQUE (company_id, barcode);

ALTER TABLE products DROP COLUMN IF EXISTS shop_id;
ALTER TABLE sales DROP COLUMN IF EXISTS shop_id;
ALTER TABLE debtors DROP COLUMN IF EXISTS shop_id;
ALTER TABLE users DROP COLUMN IF EXISTS current_shop_id;
-- +goose StatementEnd
