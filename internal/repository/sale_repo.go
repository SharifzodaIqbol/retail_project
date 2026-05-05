package repository

import (
	"context"
	"fmt"
	"retail-managment-system/internal/domain"

	"github.com/jackc/pgx/v5/pgxpool"
)

type SaleRepository struct {
	db *pgxpool.Pool
}

func NewSaleRepository(db *pgxpool.Pool) *SaleRepository {
	return &SaleRepository{db: db}
}

func (r *SaleRepository) ExecuteSale(ctx context.Context, sellerID int, items []domain.SaleItem, total float64) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var saleID int
	err = tx.QueryRow(ctx,
		"INSERT INTO sales (seller_id, total_amount) VALUES ($1, $2) RETURNING id",
		sellerID, total).Scan(&saleID)
	if err != nil {
		return err
	}

	for _, item := range items {
		// Записываем в состав чека
		_, err = tx.Exec(ctx,
			"INSERT INTO sale_items (sale_id, product_id, quantity, price_at_sale) VALUES ($1, $2, $3, $4)",
			saleID, item.ProductID, item.Quantity, item.PriceAtSale)
		if err != nil {
			return err
		}

		commandTag, err := tx.Exec(ctx,
			"UPDATE products SET stock = stock - $1 WHERE id = $2 AND stock >= $1",
			item.Quantity, item.ProductID)

		if err != nil || commandTag.RowsAffected() == 0 {
			return fmt.Errorf("недостаточно товара на складе (ID: %d)", item.ProductID)
		}
	}

	return tx.Commit(ctx)
}
