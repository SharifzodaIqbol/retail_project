package repository

import (
	"context"
	"fmt"
	"retail-managment-system/internal/domain"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type ProductRepository struct {
	db *pgxpool.Pool
}

func NewProductRepository(db *pgxpool.Pool) *ProductRepository {
	return &ProductRepository{db: db}
}

// Create — создаёт товар и, в той же транзакции, его базовую единицу
// продажи ("шт"/"кг", conversion_factor = 1, is_base = true). Базовая
// единица должна существовать всегда — на неё опирается продажа "по
// умолчанию", когда для товара ещё не завели дополнительные единицы
// (упаковку, блок...).
func (r *ProductRepository) Create(ctx context.Context, p domain.Product) (int, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx)

	var productID int
	err = tx.QueryRow(ctx, `INSERT INTO products
		(company_id, shop_id, name, barcode, buy_price, sell_price, stock, unit)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id`,
		p.CompanyID, p.ShopID, p.Name, p.Barcode, p.BuyPrice, p.SellPrice, p.Stock, p.Unit,
	).Scan(&productID)
	if err != nil {
		return 0, err
	}

	baseLabel := "дона"
	if p.Unit == domain.UnitKg {
		baseLabel = "кг"
	}
	_, err = tx.Exec(ctx, `INSERT INTO product_units
		(company_id, product_id, label, conversion_factor, price, barcode, is_base, is_active)
		VALUES ($1, $2, $3, 1, $4, $5, true, true)`,
		p.CompanyID, productID, baseLabel, p.SellPrice, p.Barcode,
	)
	if err != nil {
		return 0, err
	}

	return productID, tx.Commit(ctx)
}

// GetAll — возвращает страницу товаров текущего магазина с пагинацией.
// limit  — количество записей на странице (рекомендуется 50).
// offset — смещение (= (page-1) * limit).
func (r *ProductRepository) GetAll(ctx context.Context, companyID, shopID int, limit, offset int) ([]domain.Product, int, error) {
	// Общее количество товаров для вычисления total_pages на клиенте
	var total int
	err := r.db.QueryRow(ctx,
		`SELECT COUNT(*) FROM products WHERE is_active = true AND company_id = $1 AND shop_id = $2`,
		companyID, shopID,
	).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	query := `SELECT id, name, barcode, buy_price, sell_price, stock, unit FROM products 
              WHERE is_active = true AND company_id = $1 AND shop_id = $2 ORDER BY stock ASC
              LIMIT $3 OFFSET $4`

	rows, err := r.db.Query(ctx, query, companyID, shopID, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var products []domain.Product
	for rows.Next() {
		var p domain.Product
		if err := rows.Scan(&p.ID, &p.Name, &p.Barcode, &p.BuyPrice, &p.SellPrice, &p.Stock, &p.Unit); err != nil {
			return nil, 0, err
		}
		products = append(products, p)
	}
	if products == nil {
		products = []domain.Product{}
	}
	return products, total, nil
}

func (r *ProductRepository) GetByBarcode(ctx context.Context, companyID, shopID int, barcode string) (*domain.Product, error) {
	var p domain.Product
	query := `SELECT id, name, barcode, buy_price, sell_price, stock, unit FROM products WHERE barcode = $1 AND company_id = $2 AND shop_id = $3 AND is_active = true`

	err := r.db.QueryRow(ctx, query, barcode, companyID, shopID).Scan(
		&p.ID, &p.Name, &p.Barcode, &p.BuyPrice, &p.SellPrice, &p.Stock, &p.Unit,
	)
	if err != nil {
		return nil, err
	}
	return &p, nil
}

// GetByUnitBarcode — находит товар по штрихкоду, принадлежащему конкретной
// единице продажи (product_units.barcode), а не самому товару. Нужен для
// сканера на кассе: кассир сканирует штрихкод упаковки, а не товара в целом.
func (r *ProductRepository) GetByUnitBarcode(ctx context.Context, companyID, shopID int, barcode string) (*domain.Product, error) {
	var p domain.Product
	query := `
		SELECT p.id, p.name, p.barcode, p.buy_price, p.sell_price, p.stock, p.unit
		FROM products p
		JOIN product_units pu ON pu.product_id = p.id
		WHERE pu.barcode = $1 AND pu.company_id = $2 AND pu.is_active = true
		  AND p.company_id = $2 AND p.shop_id = $3 AND p.is_active = true`

	err := r.db.QueryRow(ctx, query, barcode, companyID, shopID).Scan(
		&p.ID, &p.Name, &p.Barcode, &p.BuyPrice, &p.SellPrice, &p.Stock, &p.Unit,
	)
	if err != nil {
		return nil, err
	}
	return &p, nil
}

// BarcodeExists — проверяет, занят ли штрихкод в рамках компании. Смотрим
// СРАЗУ в обеих таблицах: products.barcode и product_units.barcode — это
// два отдельных уникальных индекса, и код, свободный в products, вполне
// может быть уже занят чьей-то доп. единицей продажи (упаковкой другого
// товара). Раньше проверялся только products — из-за этого generateBarcode
// мог честно отдать код, который тут же падал с ошибкой уникальности при
// сохранении доп. единицы.
func (r *ProductRepository) BarcodeExists(ctx context.Context, companyID int, barcode string) (bool, error) {
	var exists bool
	err := r.db.QueryRow(ctx,
		`SELECT EXISTS(
			SELECT 1 FROM products WHERE company_id = $1 AND barcode = $2
			UNION ALL
			SELECT 1 FROM product_units WHERE company_id = $1 AND barcode = $2
		)`,
		companyID, barcode,
	).Scan(&exists)
	if err != nil {
		return false, err
	}
	return exists, nil
}

// BeginTx — открывает транзакцию для вызывающего кода. Используется там,
// где нужно объединить много операций (например, весь Excel-импорт) в одну
// транзакцию/один commit вместо отдельной транзакции на каждую строку.
func (r *ProductRepository) BeginTx(ctx context.Context) (pgx.Tx, error) {
	return r.db.Begin(ctx)
}

// LoadImportContext — загружает ОДНИМ проходом (3 запроса вместо
// O(строк файла) запросов) всё, что нужно для обработки Excel-импорта:
// все занятые штрихкоды компании, карту "имя товара -> штрихкод" в рамках
// магазина и карту "штрихкод товара -> его текущие доп. единицы". Вызывается
// один раз перед обработкой файла, дальше держится в памяти и обновляется
// по ходу импорта (см. importProducts).
func (r *ProductRepository) LoadImportContext(ctx context.Context, companyID, shopID int) (*domain.ImportContext, error) {
	impCtx := &domain.ImportContext{
		Barcodes:      make(map[string]bool),
		NameToBarcode: make(map[string]string),
		ProductLabels: make(map[string]map[string]bool),
	}

	// Все занятые в компании штрихкоды — и товаров, и доп. единиц, потому
	// что это два разных уникальных индекса, но подобранный код должен
	// быть свободен в обоих сразу (см. комментарий у прежнего BarcodeExists).
	rows, err := r.db.Query(ctx, `
		SELECT barcode FROM products WHERE company_id = $1 AND barcode IS NOT NULL
		UNION
		SELECT barcode FROM product_units WHERE company_id = $1 AND barcode IS NOT NULL`,
		companyID,
	)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var b string
		if err := rows.Scan(&b); err != nil {
			rows.Close()
			return nil, err
		}
		impCtx.Barcodes[b] = true
	}
	rows.Close()

	// Имя -> штрихкод для товаров ЭТОГО магазина — чтобы строки без
	// штрихкода при повторном импорте матчились на уже существующий товар
	// по названию, а не всегда получали новый сгенерированный штрихкод.
	rows, err = r.db.Query(ctx, `
		SELECT name, barcode FROM products
		WHERE company_id = $1 AND shop_id = $2 AND barcode IS NOT NULL`,
		companyID, shopID,
	)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var name, barcode string
		if err := rows.Scan(&name, &barcode); err != nil {
			rows.Close()
			return nil, err
		}
		impCtx.NameToBarcode[domain.NormalizeImportName(name)] = barcode
	}
	rows.Close()

	// Штрихкод товара -> набор названий его текущих доп. единиц, чтобы
	// проверять лимит MaxExtraUnitsPerProduct без SELECT на каждую строку.
	rows, err = r.db.Query(ctx, `
		SELECT p.barcode, pu.label
		FROM product_units pu
		JOIN products p ON p.id = pu.product_id
		WHERE pu.company_id = $1 AND pu.is_base = false AND pu.is_active = true
		  AND p.company_id = $1 AND p.barcode IS NOT NULL`,
		companyID,
	)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var barcode, label string
		if err := rows.Scan(&barcode, &label); err != nil {
			rows.Close()
			return nil, err
		}
		if impCtx.ProductLabels[barcode] == nil {
			impCtx.ProductLabels[barcode] = make(map[string]bool)
		}
		impCtx.ProductLabels[barcode][label] = true
	}
	rows.Close()

	return impCtx, nil
}

// SearchByName — ищет товары по названию в рамках одного магазина.
func (r *ProductRepository) SearchByName(ctx context.Context, companyID, shopID int, name string) ([]domain.Product, error) {
	query := `SELECT id, name, barcode, sell_price, stock, unit FROM products 
              WHERE company_id = $1 AND shop_id = $2 AND name ILIKE $3 AND is_active = true 
              ORDER BY name ASC LIMIT 10`

	rows, err := r.db.Query(ctx, query, companyID, shopID, "%"+name+"%")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var products []domain.Product
	for rows.Next() {
		var p domain.Product
		if err := rows.Scan(&p.ID, &p.Name, &p.Barcode, &p.SellPrice, &p.Stock, &p.Unit); err != nil {
			return nil, err
		}
		products = append(products, p)
	}
	return products, nil
}

// GetLowStockProductsByCompany — то же самое, но по всей компании сразу
// (используется в Telegram-дайджесте владельцу, который хочет видеть остатки
// сразу по всем своим магазинам, а не по одному).
func (r *ProductRepository) GetLowStockProductsByCompany(ctx context.Context, companyID int, threshold int) ([]domain.Product, error) {
	query := `SELECT id, name, stock, unit FROM products 
              WHERE stock < $1 AND is_active = true AND company_id = $2
              ORDER BY stock ASC`

	rows, err := r.db.Query(ctx, query, threshold, companyID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var products []domain.Product
	for rows.Next() {
		var p domain.Product
		if err := rows.Scan(&p.ID, &p.Name, &p.Stock, &p.Unit); err != nil {
			return nil, err
		}
		products = append(products, p)
	}
	return products, nil
}

// GetLowStockProducts
func (r *ProductRepository) GetLowStockProducts(ctx context.Context, companyID, shopID int, threshold int) ([]domain.Product, error) {
	query := `SELECT id, name, stock, unit FROM products 
              WHERE stock < $1 AND is_active = true AND company_id = $2 AND shop_id = $3
              ORDER BY stock ASC`

	rows, err := r.db.Query(ctx, query, threshold, companyID, shopID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var products []domain.Product
	for rows.Next() {
		var p domain.Product
		if err := rows.Scan(&p.ID, &p.Name, &p.Stock, &p.Unit); err != nil {
			return nil, err
		}
		products = append(products, p)
	}
	return products, nil
}

// UpdateInventory — addStock теперь float64, чтобы можно было добавлять
// дробные остатки для товаров с unit = "kg" (например, +2.5 кг), а с
// добавлением возможности продавцу уменьшать остаток — addStock может
// быть и отрицательным.
//
// Условие "stock + $1 >= 0" в WHERE не даёт остатку уйти в минус при
// гонке двух одновременных операций над одним товаром (клиентская проверка
// делается по локально закэшированному stock и могла устареть). Если из-за
// этого условия ни одна строка не была затронута, но товар при этом
// существует — значит запрошенное уменьшение больше текущего остатка,
// это отличаем от ErrNotFound отдельной ошибкой ErrInsufficientStock.
func (r *ProductRepository) UpdateInventory(ctx context.Context, id int, companyID, shopID int, addStock float64, sellPrice, buyPrice float64) error {
	query := `
		UPDATE products 
		SET 
			stock = stock + $1, 
			sell_price = $2, 
			buy_price = $3 
		WHERE id = $4 AND company_id = $5 AND shop_id = $6 AND stock + $1 >= 0`

	tag, err := r.db.Exec(ctx, query, addStock, sellPrice, buyPrice, id, companyID, shopID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() > 0 {
		return nil
	}

	// Ничего не обновилось — выясняем, товара нет вообще, или он есть,
	// но условие по остатку не выполнилось (недостаточно товара).
	var exists bool
	checkErr := r.db.QueryRow(ctx,
		`SELECT true FROM products WHERE id = $1 AND company_id = $2 AND shop_id = $3`,
		id, companyID, shopID,
	).Scan(&exists)
	if checkErr != nil {
		return ErrNotFound
	}
	return ErrInsufficientStock
}

// Update — обновляет карточку товара (название, штрихкод, цены, базовую
// единицу измерения). Остаток склада (stock) НЕ трогает — им управляет
// отдельно UpdateInventory (пополнение/списание с уведомлением владельца),
// чтобы редактирование карточки не могло случайно исказить складской учёт.
// Заодно синхронизирует БАЗОВУЮ единицу продажи (product_units, is_base =
// true) — её ярлык ("шт"/"кг"), цена и штрихкод должны оставаться зеркалом
// этих же полей товара, иначе касса и карточка разойдутся.
func (r *ProductRepository) Update(ctx context.Context, id, companyID, shopID int, p domain.Product) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(ctx, `UPDATE products
		SET name = $1, barcode = $2, buy_price = $3, sell_price = $4, unit = $5
		WHERE id = $6 AND company_id = $7 AND shop_id = $8`,
		p.Name, p.Barcode, p.BuyPrice, p.SellPrice, p.Unit, id, companyID, shopID,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}

	baseLabel := "дона"
	if p.Unit == domain.UnitKg {
		baseLabel = "кг"
	}
	_, err = tx.Exec(ctx, `UPDATE product_units
		SET label = $1, price = $2, barcode = $3
		WHERE product_id = $4 AND company_id = $5 AND is_base = true`,
		baseLabel, p.SellPrice, p.Barcode, id, companyID,
	)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

func (r *ProductRepository) Delete(ctx context.Context, id int, companyID, shopID int) error {
	tag, err := r.db.Exec(ctx, "DELETE FROM products WHERE id = $1 AND company_id = $2 AND shop_id = $3", id, companyID, shopID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *ProductRepository) GetNameByID(ctx context.Context, id int, companyID, shopID int) (string, error) {
	query := `SELECT name FROM products WHERE id = $1 AND company_id = $2 AND shop_id = $3`
	var name string
	err := r.db.QueryRow(ctx, query, id, companyID, shopID).Scan(&name)
	if err != nil {
		return "", err
	}
	return name, nil
}

// UpsertFromImportRow — то же самое, что раньше делал UpsertFromImport, но
// рассчитано на пакетную обработку всего файла импорта:
//
//   - tx — САМА транзакция уже открыта вызывающим кодом (см. handler
//     importProducts) ОДИН раз на весь файл, а не на каждую строку. Здесь
//     ожидается вложенная транзакция (tx.Begin(ctx) от уже открытой tx),
//     что в pgx реализуется через SAVEPOINT: если эта строка провалится
//     (например, нарушение constraint'а), вызывающий код откатывает только
//     её через Rollback этой вложенной tx, а не весь файл целиком.
//   - impCtx — предзагруженный ImportContext (см. LoadImportContext), сюда
//     не ходим в БД за проверками, которые можно сделать по данным,
//     загруженным один раз перед циклом.
//
// Возвращает true, если была операция INSERT (новый товар), и false, если был UPDATE.
func (r *ProductRepository) UpsertFromImportRow(ctx context.Context, tx pgx.Tx, p domain.Product, extraUnits []domain.CreateProductUnitRequest, impCtx *domain.ImportContext) (created bool, err error) {
	var productID int
	query := `
		INSERT INTO products (company_id, shop_id, name, barcode, buy_price, sell_price, stock, unit, is_active)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, true)
		ON CONFLICT (company_id, shop_id, barcode) DO UPDATE SET
			name       = EXCLUDED.name,
			buy_price  = EXCLUDED.buy_price,
			sell_price = EXCLUDED.sell_price,
			stock      = EXCLUDED.stock,
			unit       = EXCLUDED.unit,
			is_active  = true
		RETURNING id, (xmax = 0) AS inserted`

	err = tx.QueryRow(ctx, query,
		p.CompanyID, p.ShopID, p.Name, p.Barcode, p.BuyPrice, p.SellPrice, p.Stock, p.Unit,
	).Scan(&productID, &created)
	if err != nil {
		return false, err
	}

	baseLabel := "дона"
	if p.Unit == domain.UnitKg {
		baseLabel = "кг"
	}
	// upsert базовой единицы: она либо ещё не существует (новый товар —
	// INSERT), либо уже есть и её нужно обновить под актуальные
	// цену/штрихкод из этого же файла импорта (UPDATE по product_id+is_base).
	_, err = tx.Exec(ctx, `
		INSERT INTO product_units (company_id, product_id, label, conversion_factor, price, barcode, is_base, is_active)
		VALUES ($1, $2, $3, 1, $4, $5, true, true)
		ON CONFLICT (product_id) WHERE is_base = true DO UPDATE SET
			label   = EXCLUDED.label,
			price   = EXCLUDED.price,
			barcode = EXCLUDED.barcode`,
		p.CompanyID, productID, baseLabel, p.SellPrice, p.Barcode,
	)
	if err != nil {
		return false, err
	}

	// Проверяем лимит ДО вставки: у товара уже могло быть до
	// domain.MaxExtraUnitsPerProduct доп. единиц (заведённых вручную через
	// приложение или предыдущим импортом), и импорт с новыми названиями
	// единиц (не совпадающими с уже существующими по label) не должен
	// пробить общий лимит — та же защита, что и в createProductUnit, но
	// здесь речь о ПОВТОРНОМ импорте уже существующего товара. Данные для
	// этой проверки уже загружены один раз в impCtx (LoadImportContext) —
	// без SELECT на каждую строку файла.
	existingLabels := impCtx.ProductLabels[*p.Barcode]
	if existingLabels == nil {
		existingLabels = make(map[string]bool)
	} else {
		// Копируем, чтобы не мутировать общую карту до успешного commit'а
		// этой строки — если строка провалится, лимит для товара не
		// должен "запомнить" единицы, которые в итоге не сохранились.
		copied := make(map[string]bool, len(existingLabels))
		for k := range existingLabels {
			copied[k] = true
		}
		existingLabels = copied
	}

	existingCount := len(existingLabels)
	totalAfter := existingCount
	for _, u := range extraUnits {
		if !existingLabels[u.Label] {
			existingLabels[u.Label] = true
			totalAfter++
		}
	}
	if totalAfter > domain.MaxExtraUnitsPerProduct {
		return false, fmt.Errorf(
			"маҳсулот аллакай %d воҳиди иловагӣ дорад, ҳадди аксар %d иҷозат дода мешавад",
			existingCount, domain.MaxExtraUnitsPerProduct,
		)
	}

	// Дополнительные единицы продажи из этой же строки (упаковка/блок/...).
	// Импорт не пытается угадать conflict-семантику для них по штрихкоду —
	// каждый повторный импорт того же файла просто добавит их заново было
	// бы неверно, поэтому матчим по (product_id, label): если единица с
	// таким названием у товара уже есть — обновляем, иначе создаём.
	for _, u := range extraUnits {
		_, err = tx.Exec(ctx, `
			INSERT INTO product_units (company_id, product_id, label, conversion_factor, price, barcode, is_base, is_active)
			VALUES ($1, $2, $3, $4, $5, $6, false, true)
			ON CONFLICT (product_id, label) WHERE NOT is_base DO UPDATE SET
				conversion_factor = EXCLUDED.conversion_factor,
				price             = EXCLUDED.price,
				barcode           = EXCLUDED.barcode`,
			p.CompanyID, productID, u.Label, u.ConversionFactor, u.Price, u.Barcode,
		)
		if err != nil {
			return false, err
		}
	}

	// Строка успешно обработана — обновляем impCtx, чтобы последующие
	// строки ЭТОГО ЖЕ файла видели актуальное состояние (например, если
	// в файле дважды встречается один и тот же товар без штрихкода —
	// вторая строка должна найти штрихкод, сгенерированный для первой,
	// а не сгенерировать ещё один).
	impCtx.Barcodes[*p.Barcode] = true
	impCtx.NameToBarcode[domain.NormalizeImportName(p.Name)] = *p.Barcode
	if len(extraUnits) > 0 {
		labels := impCtx.ProductLabels[*p.Barcode]
		if labels == nil {
			labels = make(map[string]bool)
			impCtx.ProductLabels[*p.Barcode] = labels
		}
		for _, u := range extraUnits {
			labels[u.Label] = true
		}
		for _, u := range extraUnits {
			if b := u.Barcode; b != nil && *b != "" {
				impCtx.Barcodes[*b] = true
			}
		}
	}

	return created, nil
}
