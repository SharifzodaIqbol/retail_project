-- +goose Up
-- +goose StatementBegin
-- КРИТИЧЕСКИЙ ФИКС ИЗОЛЯЦИИ ДАННЫХ:
-- таблица sales не имела company_id, поэтому все запросы по продажам и
-- аналитике (история чеков, отмена чека, выручка, топ товаров, статистика
-- продавцов) были глобальными и показывали/изменяли данные ВСЕХ компаний.

ALTER TABLE sales ADD COLUMN company_id INTEGER REFERENCES companies(id) ON DELETE CASCADE;

-- Backfill для существующих строк: берём company_id продавца, который сделал продажу
UPDATE sales s
SET company_id = u.company_id
FROM users u
WHERE s.seller_id = u.id AND s.company_id IS NULL;

-- На случай, если seller_id оказался NULL (продавец удалён) — пробуем восстановить
-- company_id через товары в чеке.
UPDATE sales s
SET company_id = p.company_id
FROM sale_items si
JOIN products p ON p.id = si.product_id
WHERE s.id = si.sale_id AND s.company_id IS NULL;

-- Если остались строки без company_id (например, чек без позиций и без
-- продавца — потерянные/мусорные данные), отмечаем их отдельной "служебной"
-- компанией, чтобы NOT NULL не сломал миграцию на проде. Такие чеки стоит
-- проверить руками после миграции.
DO $$
DECLARE
    orphan_count INTEGER;
    fallback_company_id INTEGER;
BEGIN
    SELECT COUNT(*) INTO orphan_count FROM sales WHERE company_id IS NULL;
    IF orphan_count > 0 THEN
        INSERT INTO companies (name, billing_plan, trial_ends_at, is_paid)
        VALUES ('__orphaned_sales_data__', 'trial', NOW(), false)
        RETURNING id INTO fallback_company_id;

        UPDATE sales SET company_id = fallback_company_id WHERE company_id IS NULL;

        RAISE NOTICE '% orphaned sales rows moved to placeholder company_id=%. Please review manually.', orphan_count, fallback_company_id;
    END IF;
END $$;

ALTER TABLE sales ALTER COLUMN company_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sales_company_id ON sales(company_id);
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
ALTER TABLE sales DROP COLUMN IF EXISTS company_id;
-- +goose StatementEnd
