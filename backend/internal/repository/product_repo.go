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
	(name, barcode, buy_price, sell_price, stock) VALUES ($1, $2, $3, $4, $5)`
	_, err := r.db.Exec(ctx, query, p.Name, p.Barcode, p.BuyPrice, p.SellPrice, p.Stock)
	return err
}

func (r *ProductRepository) GetAll(ctx context.Context) ([]domain.Product, error) {
	query := `SELECT id, name, barcode, buy_price, sell_price, stock FROM products 
              WHERE is_active = true ORDER BY name ASC`

	rows, err := r.db.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var products []domain.Product
	for rows.Next() {
		var p domain.Product
		if err := rows.Scan(&p.ID, &p.Name, &p.Barcode, &p.BuyPrice, &p.SellPrice, &p.Stock); err != nil {
			return nil, err
		}
		products = append(products, p)
	}
	return products, nil
}

func (r *ProductRepository) GetByBarcode(ctx context.Context, barcode string) (*domain.Product, error) {
	var p domain.Product
	query := `SELECT id, name, barcode, buy_price, sell_price, stock FROM products WHERE barcode = $1 AND is_active = true`

	err := r.db.QueryRow(ctx, query, barcode).Scan(
		&p.ID, &p.Name, &p.Barcode, &p.BuyPrice, &p.SellPrice, &p.Stock,
	)
	if err != nil {
		return nil, err
	}
	return &p, nil
}

func (r *ProductRepository) SearchByName(ctx context.Context, name string) ([]domain.Product, error) {
	query := `SELECT id, name, barcode, sell_price, stock FROM products 
              WHERE name ILIKE $1 AND is_active = true LIMIT 10`

	rows, err := r.db.Query(ctx, query, "%"+name+"%")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var products []domain.Product
	for rows.Next() {
		var p domain.Product
		if err := rows.Scan(&p.ID, &p.Name, &p.Barcode, &p.SellPrice, &p.Stock); err != nil {
			return nil, err
		}
		products = append(products, p)
	}
	return products, nil
}

func (r *ProductRepository) GetLowStockProducts(ctx context.Context, threshold int) ([]domain.Product, error) {
	query := `SELECT id, name, stock FROM products 
              WHERE stock < $1 AND is_active = true 
              ORDER BY stock ASC`

	rows, err := r.db.Query(ctx, query, threshold)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var products []domain.Product
	for rows.Next() {
		var p domain.Product
		if err := rows.Scan(&p.ID, &p.Name, &p.Stock); err != nil {
			return nil, err
		}
		products = append(products, p)
	}
	return products, nil
}

func (r *ProductRepository) UpdateInventory(ctx context.Context, id int, addStock int, sellPrice, buyPrice float64) error {
	query := `
		UPDATE products 
		SET 
			stock = stock + $1, 
			sell_price = $2, 
			buy_price = $3 
		WHERE id = $4`

	_, err := r.db.Exec(ctx, query, addStock, sellPrice, buyPrice, id)
	return err
}

// SoftDelete — помечает товар как неактивный (не удаляет физически)
func (r *ProductRepository) SoftDelete(ctx context.Context, id int) error {
	_, err := r.db.Exec(ctx, "UPDATE products SET is_active = false WHERE id = $1", id)
	return err
}
