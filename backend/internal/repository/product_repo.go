// Создай файл internal/repository/product_repo.go
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
func (r *ProductRepository) GetByBarcode(ctx context.Context, barcode string) (*domain.Product, error) {
	var p domain.Product
	query := `SELECT id, name, barcode, buy_price, sell_price, stock FROM products WHERE barcode = $1`

	err := r.db.QueryRow(ctx, query, barcode).Scan(
		&p.ID, &p.Name, &p.Barcode, &p.BuyPrice, &p.SellPrice, &p.Stock,
	)
	if err != nil {
		return nil, err
	}
	return &p, nil
}
func (r *ProductRepository) SearchByName(ctx context.Context, name string) ([]domain.Product, error) {
	// Ищем товары, где название содержит введенную строку
	query := `SELECT id, name, barcode, buy_price, sell_price, stock FROM products 
              WHERE name ILIKE $1 AND is_active = true`

	rows, err := r.db.Query(ctx, query, "%"+name+"%")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var products []domain.Product
	for rows.Next() {
		var p domain.Product
		err := rows.Scan(&p.ID, &p.Name, &p.Barcode, &p.BuyPrice, &p.SellPrice, &p.Stock)
		if err != nil {
			return nil, err
		}
		products = append(products, p)
	}
	return products, nil
}
