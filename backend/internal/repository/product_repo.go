package repository

import (
	"context"
	"retail-managment-system/internal/domain"

	"github.com/jackc/pgx/v5/pgxpool"
)

type ProductRepository struct {
	db *pgxpool.Pool
}

func NewProductRepository(db *pgxpool.Pool) *ProductRepository {
	return &ProductRepository{db: db}
}

func (r *ProductRepository) Create(ctx context.Context, p domain.Product) error {
	query := `INSERT INTO products 
	(company_id, shop_id, name, barcode, buy_price, sell_price, stock, unit) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`
	_, err := r.db.Exec(ctx, query, p.CompanyID, p.ShopID, p.Name, p.Barcode, p.BuyPrice, p.SellPrice, p.Stock, p.Unit)
	return err
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

func (r *ProductRepository) SoftDelete(ctx context.Context, id int, companyID, shopID int) error {
	tag, err := r.db.Exec(ctx, "UPDATE products SET is_active = false WHERE id = $1 AND company_id = $2 AND shop_id = $3", id, companyID, shopID)
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

// UpsertFromImport — создаёт товар или, если в этом магазине уже есть товар
// с таким баркодом, обновляет его (название/цены/остаток/единицу).
// Возвращает true, если была операция INSERT (новый товар), и false, если был UPDATE.
func (r *ProductRepository) UpsertFromImport(ctx context.Context, p domain.Product) (created bool, err error) {
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
		RETURNING (xmax = 0) AS inserted`

	err = r.db.QueryRow(ctx, query,
		p.CompanyID, p.ShopID, p.Name, p.Barcode, p.BuyPrice, p.SellPrice, p.Stock, p.Unit,
	).Scan(&created)
	return created, err
}
