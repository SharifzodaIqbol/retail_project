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

func (r *SaleRepository) ExecuteSale(ctx context.Context, sellerID int, items []domain.SaleItem, total float64) (int, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx)

	var saleID int
	err = tx.QueryRow(ctx,
		"INSERT INTO sales (seller_id, total_amount) VALUES ($1, $2) RETURNING id",
		sellerID, total).Scan(&saleID)
	if err != nil {
		return 0, err
	}

	for _, item := range items {
		// Записываем в состав чека
		_, err = tx.Exec(ctx,
			"INSERT INTO sale_items (sale_id, product_id, quantity, price_at_sale) VALUES ($1, $2, $3, $4)",
			saleID, item.ProductID, item.Quantity, item.PriceAtSale)
		if err != nil {
			return 0, err
		}

		commandTag, err := tx.Exec(ctx,
			"UPDATE products SET stock = stock - $1 WHERE id = $2 AND stock >= $1",
			item.Quantity, item.ProductID)

		if err != nil || commandTag.RowsAffected() == 0 {
			return 0, fmt.Errorf("недостаточно товара на складе (ID: %d)", item.ProductID)
		}
	}

	return saleID, tx.Commit(ctx)
}
func (r *SaleRepository) GetTodayTotal(ctx context.Context) (float64, error) {
	var total float64
	// Считаем сумму всех продаж, которые не были отменены, за текущие сутки
	query := `SELECT COALESCE(SUM(total_amount), 0) FROM sales WHERE created_at > CURRENT_DATE AND is_cancelled = false`
	err := r.db.QueryRow(ctx, query).Scan(&total)
	if err != nil {
		return 0, err
	}
	return total, err
}
func (r *SaleRepository) GetTopProducts(ctx context.Context, limit int) (string, error) {
	query := `
        SELECT p.name, SUM(si.quantity) as total_qty
        FROM sale_items si
        JOIN products p ON si.product_id = p.id
        GROUP BY p.name
        ORDER BY total_qty DESC
        LIMIT $1`

	rows, err := r.db.Query(ctx, query, limit)
	if err != nil {
		return "", err
	}
	defer rows.Close()

	report := "🔝 **Топ товаров:**\n"
	for rows.Next() {
		var name string
		var qty int
		if err := rows.Scan(&name, &qty); err != nil {
			continue
		}
		report += fmt.Sprintf("- %s: %d шт.\n", name, qty)
	}
	return report, nil
}
