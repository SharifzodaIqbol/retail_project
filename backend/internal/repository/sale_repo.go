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

func (r *SaleRepository) ExecuteSale(ctx context.Context, sellerID int, items []domain.SaleItem, total float64) (int, []domain.Product, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return 0, nil, err
	}
	defer tx.Rollback(ctx)

	var saleID int
	err = tx.QueryRow(ctx,
		"INSERT INTO sales (seller_id, total_amount) VALUES ($1, $2) RETURNING id",
		sellerID, total).Scan(&saleID)
	if err != nil {
		return 0, nil, err
	}

	var lowStockProducts []domain.Product

	for _, item := range items {
		_, err = tx.Exec(ctx,
			"INSERT INTO sale_items (sale_id, product_id, quantity, price_at_sale) VALUES ($1, $2, $3, $4)",
			saleID, item.ProductID, item.Quantity, item.PriceAtSale)
		if err != nil {
			return 0, nil, err
		}

		var p domain.Product
		err = tx.QueryRow(ctx, `
            UPDATE products 
            SET stock = stock - $1 
            WHERE id = $2 AND stock >= $1 
            RETURNING name, stock`,
			item.Quantity, item.ProductID).Scan(&p.Name, &p.Stock)

		if err != nil {
			return 0, nil, fmt.Errorf("недостаточно товара ID: %d", item.ProductID)
		}

		if p.Stock < 10 {
			lowStockProducts = append(lowStockProducts, p)
		}
	}
	return saleID, lowStockProducts, tx.Commit(ctx)
}

func (r *SaleRepository) GetTodayTotal(ctx context.Context) (domain.DailyStats, error) {
	var stats domain.DailyStats
	query := `
		SELECT 
			COALESCE(SUM(total_amount), 0), 
			COUNT(id) 
		FROM sales 
		WHERE created_at >= CURRENT_DATE 
		AND is_canceled = false`

	err := r.db.QueryRow(ctx, query).Scan(&stats.Total, &stats.Count)
	return stats, err
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

func (r *SaleRepository) GetAll(ctx context.Context) ([]domain.Sale, error) {
	query := `
        SELECT s.id, s.seller_id, u.username, s.total_amount, s.is_canceled, s.cancel_reason,
               TO_CHAR(s.created_at, 'DD.MM.YYYY HH24:MI') as created_at
        FROM sales s
        LEFT JOIN users u ON s.seller_id = u.id
        ORDER BY s.id DESC
        LIMIT 200`

	rows, err := r.db.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var sales []domain.Sale

	for rows.Next() {
		var s domain.Sale
		err := rows.Scan(
			&s.ID, &s.SellerID, &s.SellerName, &s.TotalAmount,
			&s.IsCanceled, &s.CancelReason, &s.CreatedAt,
		)
		if err != nil {
			return nil, err
		}
		sales = append(sales, s)
	}

	return sales, rows.Err()
}

func (r *SaleRepository) CancelSale(ctx context.Context, saleID int, reason string) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	updateStockQuery := `
        UPDATE products 
        SET stock = stock + si.quantity 
        FROM sale_items si 
        WHERE products.id = si.product_id AND si.sale_id = $1`

	_, err = tx.Exec(ctx, updateStockQuery, saleID)
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx, "UPDATE sales SET is_canceled = true, cancel_reason = $1 WHERE id = $2", reason, saleID)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

func (r *SaleRepository) GetDailyNetProfit(ctx context.Context) (float64, error) {
	var profit float64
	query := `
        SELECT 
            COALESCE(SUM(si.quantity * (si.price_at_sale - p.buy_price)), 0)
        FROM sale_items si
        JOIN products p ON si.product_id = p.id
        JOIN sales s ON si.sale_id = s.id
        WHERE s.is_canceled = false 
          AND s.created_at >= CURRENT_DATE`

	err := r.db.QueryRow(ctx, query).Scan(&profit)
	return profit, err
}

// ─── НОВЫЕ методы аналитики ────────────────────────────────────────────────

func (r *SaleRepository) GetPeriodSummary(ctx context.Context, period string) (domain.PeriodSummary, error) {
	var dateFilter string
	switch period {
	case "week":
		dateFilter = "created_at >= CURRENT_DATE - INTERVAL '7 days'"
	case "month":
		dateFilter = "created_at >= DATE_TRUNC('month', CURRENT_DATE)"
	default: // today
		dateFilter = "created_at >= CURRENT_DATE"
	}

	var summary domain.PeriodSummary
	query := fmt.Sprintf(`
		SELECT 
			COALESCE(SUM(s.total_amount), 0) as revenue,
			COALESCE(SUM(si.quantity * (si.price_at_sale - p.buy_price)), 0) as profit,
			COUNT(DISTINCT s.id) as sales_count,
			COALESCE(AVG(s.total_amount), 0) as avg_check
		FROM sales s
		LEFT JOIN sale_items si ON s.id = si.sale_id
		LEFT JOIN products p ON si.product_id = p.id
		WHERE s.is_canceled = false AND s.%s`, dateFilter)

	err := r.db.QueryRow(ctx, query).Scan(
		&summary.Revenue, &summary.Profit, &summary.SalesCount, &summary.AvgCheck,
	)
	return summary, err
}

func (r *SaleRepository) GetTopProductsDetailed(ctx context.Context, limit int) ([]domain.TopProduct, error) {
	query := `
        SELECT 
            p.id,
            p.name, 
            SUM(si.quantity) as total_qty,
            SUM(si.quantity * si.price_at_sale) as total_revenue,
            SUM(si.quantity * (si.price_at_sale - p.buy_price)) as total_profit
        FROM sale_items si
        JOIN products p ON si.product_id = p.id
        JOIN sales s ON si.sale_id = s.id
        WHERE s.is_canceled = false
        GROUP BY p.id, p.name
        ORDER BY total_qty DESC
        LIMIT $1`

	rows, err := r.db.Query(ctx, query, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var products []domain.TopProduct
	for rows.Next() {
		var p domain.TopProduct
		if err := rows.Scan(&p.ProductID, &p.Name, &p.TotalQty, &p.TotalRev, &p.TotalProfit); err != nil {
			continue
		}
		products = append(products, p)
	}
	return products, nil
}

func (r *SaleRepository) GetSalesByDay(ctx context.Context, days int) ([]domain.SaleByDay, error) {
	query := `
        SELECT 
            TO_CHAR(s.created_at::date, 'DD.MM') as date,
            COALESCE(SUM(s.total_amount), 0) as revenue,
            COALESCE(SUM(si.quantity * (si.price_at_sale - p.buy_price)), 0) as profit,
            COUNT(DISTINCT s.id) as count
        FROM generate_series(
            CURRENT_DATE - ($1 - 1) * INTERVAL '1 day',
            CURRENT_DATE,
            INTERVAL '1 day'
        ) as d(day)
        LEFT JOIN sales s ON s.created_at::date = d.day AND s.is_canceled = false
        LEFT JOIN sale_items si ON s.id = si.sale_id
        LEFT JOIN products p ON si.product_id = p.id
        GROUP BY d.day
        ORDER BY d.day ASC`

	rows, err := r.db.Query(ctx, query, days)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []domain.SaleByDay
	for rows.Next() {
		var d domain.SaleByDay
		if err := rows.Scan(&d.Date, &d.Revenue, &d.Profit, &d.Count); err != nil {
			continue
		}
		result = append(result, d)
	}
	return result, nil
}

func (r *SaleRepository) GetSellerStats(ctx context.Context) ([]domain.SellerStat, error) {
	query := `
        SELECT 
            s.seller_id,
            u.username,
            COUNT(DISTINCT s.id) as sales_count,
            COALESCE(SUM(s.total_amount), 0) as total_revenue
        FROM sales s
        JOIN users u ON s.seller_id = u.id
        WHERE s.is_canceled = false
          AND s.created_at >= CURRENT_DATE
        GROUP BY s.seller_id, u.username
        ORDER BY total_revenue DESC`

	rows, err := r.db.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var stats []domain.SellerStat
	for rows.Next() {
		var s domain.SellerStat
		if err := rows.Scan(&s.SellerID, &s.Username, &s.SalesCount, &s.TotalRev); err != nil {
			continue
		}
		stats = append(stats, s)
	}
	return stats, nil
}
