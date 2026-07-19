package repository

import (
	"context"
	"fmt"
	"log"
	"retail-managment-system/internal/domain"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type SaleRepository struct {
	db *pgxpool.Pool
}

func NewSaleRepository(db *pgxpool.Pool) *SaleRepository {
	return &SaleRepository{db: db}
}

// ExecuteSale — создаёт продажу строго в рамках одного магазина.
// ВАЖНО: company_id и shop_id записываются в sales, и каждая позиция чека
// проверяется на принадлежность тому же магазину (нельзя продать и списать
// со склада товар другого магазина/компании, передав чужой product_id).
func (r *SaleRepository) ExecuteSale(ctx context.Context, companyID, shopID int, sellerID int, items []domain.SaleItem, total float64) (int, []domain.Product, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return 0, nil, err
	}
	defer tx.Rollback(ctx)

	var saleID int
	err = tx.QueryRow(ctx,
		"INSERT INTO sales (company_id, shop_id, seller_id, total_amount) VALUES ($1, $2, $3, $4) RETURNING id",
		companyID, shopID, sellerID, total).Scan(&saleID)
	if err != nil {
		return 0, nil, err
	}

	var lowStockProducts []domain.Product

	for _, item := range items {
		_, err = tx.Exec(ctx, `INSERT INTO sale_items 
						   (sale_id, company_id, product_id, quantity, price_at_sale) 
						   VALUES ($1, $2, $3, $4, $5)`,
			saleID, companyID, item.ProductID, item.Quantity, item.PriceAtSale)
		if err != nil {
			return 0, nil, err
		}

		var p domain.Product
		// company_id/shop_id — не даём списать склад товара, принадлежащего другому магазину
		err = tx.QueryRow(ctx, `UPDATE products 
								SET stock = stock - $1 
								WHERE id = $2 AND company_id = $3 AND shop_id = $4 AND stock >= $1 
								RETURNING name, stock`,
			item.Quantity, item.ProductID, companyID, shopID).Scan(&p.Name, &p.Stock)

		if err != nil {
			return 0, nil, fmt.Errorf("недостаточно товара ID: %d", item.ProductID)
		}

		if p.Stock < 10 {
			lowStockProducts = append(lowStockProducts, p)
		}
	}
	return saleID, lowStockProducts, tx.Commit(ctx)
}

func (r *SaleRepository) GetTodayTotal(ctx context.Context, companyID int) (domain.DailyStats, error) {
	var stats domain.DailyStats
	query := `
		SELECT 
			COALESCE(SUM(total_amount), 0), 
			COUNT(id) 
		FROM sales 
		WHERE created_at >= CURRENT_DATE 
		AND is_canceled = false
		AND company_id = $1`

	err := r.db.QueryRow(ctx, query, companyID).Scan(&stats.Total, &stats.Count)
	return stats, err
}

func (r *SaleRepository) GetTopProducts(ctx context.Context, companyID int, limit int) (string, error) {
	query := `
        SELECT p.name, SUM(si.quantity) as total_qty, p.unit
        FROM sale_items si
        JOIN products p ON si.product_id = p.id
        JOIN sales s ON si.sale_id = s.id
        WHERE s.company_id = $1
        GROUP BY p.name, p.unit
        ORDER BY total_qty DESC
        LIMIT $2`

	rows, err := r.db.Query(ctx, query, companyID, limit)
	if err != nil {
		log.Println(err)
		return "", err
	}
	defer rows.Close()

	report := "🔝 **Маҳсулотҳои бисер харида шуда!**\n"
	for rows.Next() {
		var name string
		var unit string
		var qty float64

		if err := rows.Scan(&name, &qty, &unit); err != nil {
			continue
		}
		if unit == "kg" {
			unit = "кг"
		} else {
			unit = "дона"
		}
		report += fmt.Sprintf("- %s: %g %s\n", name, qty, unit)
	}
	return report, nil
}

// GetAll — возвращает страницу истории продаж текущего магазина с пагинацией.
// limit  — количество записей на странице (рекомендуется 50).
// offset — смещение (= (page-1) * limit).
func (r *SaleRepository) GetAll(ctx context.Context, companyID, shopID int, limit, offset int) ([]domain.Sale, int, error) {
	// Общее количество для вычисления total_pages
	var total int
	err := r.db.QueryRow(ctx,
		`SELECT COUNT(*) FROM sales WHERE company_id = $1 AND shop_id = $2`,
		companyID, shopID,
	).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	query := `
        SELECT s.id, s.seller_id, u.username, s.total_amount, s.is_canceled, s.cancel_reason,
               TO_CHAR(s.created_at, 'DD.MM.YYYY HH24:MI') as created_at
        FROM sales s
        LEFT JOIN users u ON s.seller_id = u.id
        WHERE s.company_id = $1 AND s.shop_id = $2
        ORDER BY s.id DESC
        LIMIT $3 OFFSET $4`

	rows, err := r.db.Query(ctx, query, companyID, shopID, limit, offset)
	if err != nil {
		return nil, 0, err
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
			return nil, 0, err
		}
		sales = append(sales, s)
	}
	if sales == nil {
		sales = []domain.Sale{}
	}

	return sales, total, rows.Err()
}

// CancelSale — отменяет чек строго внутри своего магазина.
// companyID/shopID добавлены в WHERE, чтобы владелец одного магазина не мог
// отменить (и тем самым вернуть на склад товар) чужой чек по его ID.
func (r *SaleRepository) CancelSale(ctx context.Context, companyID, shopID int, saleID int, reason string) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var exists bool
	err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM sales WHERE id = $1 AND company_id = $2 AND shop_id = $3)`, saleID, companyID, shopID).Scan(&exists)
	if err != nil {
		return err
	}
	if !exists {
		return fmt.Errorf("чек не найден")
	}

	updateStockQuery := `
        UPDATE products 
        SET stock = stock + si.quantity 
        FROM sale_items si 
        WHERE products.id = si.product_id AND si.sale_id = $1`

	_, err = tx.Exec(ctx, updateStockQuery, saleID)
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx, "UPDATE sales SET is_canceled = true, cancel_reason = $1 WHERE id = $2 AND company_id = $3 AND shop_id = $4", reason, saleID, companyID, shopID)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

// GetSaleTotal — возвращает сумму чека, только если он принадлежит магазину
func (r *SaleRepository) GetSaleTotal(ctx context.Context, companyID, shopID int, saleID int) (float64, error) {
	var total float64
	err := r.db.QueryRow(ctx, "SELECT total_amount FROM sales WHERE id = $1 AND company_id = $2 AND shop_id = $3", saleID, companyID, shopID).Scan(&total)
	return total, err
}

func (r *SaleRepository) GetDailyNetProfit(ctx context.Context, companyID int) (float64, error) {
	var profit float64
	query := `
        SELECT 
            COALESCE(SUM(si.quantity * (si.price_at_sale - p.buy_price)), 0)
        FROM sale_items si
        JOIN products p ON si.product_id = p.id
        JOIN sales s ON si.sale_id = s.id
        WHERE s.is_canceled = false 
          AND s.created_at >= CURRENT_DATE
          AND s.company_id = $1`

	err := r.db.QueryRow(ctx, query, companyID).Scan(&profit)
	return profit, err
}

// ─── НОВЫЕ методы аналитики ────────────────────────────────────────────────

func (r *SaleRepository) GetPeriodSummary(ctx context.Context, companyID, shopID int, from, to time.Time) (domain.PeriodSummary, error) {
	var summary domain.PeriodSummary
	query := `
		SELECT 
			COALESCE(SUM(s.total_amount), 0) as revenue,
			COALESCE(SUM(si.quantity * (si.price_at_sale - p.buy_price)), 0) as profit,
			COUNT(DISTINCT s.id) as sales_count,
			COALESCE(AVG(s.total_amount), 0) as avg_check
		FROM sales s
		LEFT JOIN sale_items si ON s.id = si.sale_id
		LEFT JOIN products p ON si.product_id = p.id
		WHERE s.is_canceled = false AND s.company_id = $1 AND s.shop_id = $2
		  AND s.created_at >= $3 AND s.created_at < $4`

	err := r.db.QueryRow(ctx, query, companyID, shopID, from, to).Scan(
		&summary.Revenue, &summary.Profit, &summary.SalesCount, &summary.AvgCheck,
	)
	return summary, err
}

func (r *SaleRepository) GetTopProductsDetailed(ctx context.Context, companyID, shopID int, from, to time.Time, limit int) ([]domain.TopProduct, error) {
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
        WHERE s.is_canceled = false AND s.company_id = $1 AND s.shop_id = $2
          AND s.created_at >= $3 AND s.created_at < $4
        GROUP BY p.id, p.name
        ORDER BY total_qty DESC
        LIMIT $5`

	rows, err := r.db.Query(ctx, query, companyID, shopID, from, to, limit)
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

func (r *SaleRepository) GetSalesByDay(ctx context.Context, companyID, shopID int, days int) ([]domain.SaleByDay, error) {
	query := `
    WITH daily_series AS (
        SELECT generate_series(
            CURRENT_DATE - ($1 - 1) * INTERVAL '1 day',
            CURRENT_DATE,
            INTERVAL '1 day'
        )::date as day
    ),
    daily_sales AS (
        SELECT 
            s.created_at::date as sale_date,
            SUM(s.total_amount) as total_revenue,
            COUNT(s.id) as sales_count,
            SUM(i.profit_per_sale) as total_profit
        FROM sales s
        LEFT JOIN (
            SELECT 
                si.sale_id,
                SUM(si.quantity * (si.price_at_sale - p.buy_price)) as profit_per_sale
            FROM sale_items si
            JOIN products p ON si.product_id = p.id
            GROUP BY si.sale_id
        ) i ON s.id = i.sale_id
        WHERE s.is_canceled = false AND s.company_id = $2 AND s.shop_id = $3
        GROUP BY s.created_at::date
    )
    SELECT 
        TO_CHAR(ds.day, 'DD.MM') as date,
        COALESCE(ds_val.total_revenue, 0) as revenue,
        COALESCE(ds_val.total_profit, 0) as profit,
        COALESCE(ds_val.sales_count, 0) as count
    FROM daily_series ds
    LEFT JOIN daily_sales ds_val ON ds.day = ds_val.sale_date
    ORDER BY ds.day ASC`

	rows, err := r.db.Query(ctx, query, days, companyID, shopID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []domain.SaleByDay
	for rows.Next() {
		var d domain.SaleByDay
		if err := rows.Scan(&d.Date, &d.Revenue, &d.Profit, &d.Count); err != nil {
			return nil, fmt.Errorf("scan sales by day row: %w", err)
		}
		result = append(result, d)
	}
	return result, nil
}

// GetSellerStats — продажи по каждому продавцу за произвольный период
// (от/до), а не только за сегодня — чтобы владелец мог сравнить продавцов
// за неделю, месяц или любой выбранный диапазон дат.
func (r *SaleRepository) GetSellerStats(ctx context.Context, companyID, shopID int, from, to time.Time) ([]domain.SellerStat, error) {
	query := `
        SELECT 
            s.seller_id,
            u.username,
            COUNT(DISTINCT s.id) as sales_count,
            COALESCE(SUM(s.total_amount), 0) as total_revenue
        FROM sales s
        JOIN users u ON s.seller_id = u.id
        WHERE s.is_canceled = false
          AND s.created_at >= $3 AND s.created_at < $4
          AND s.company_id = $1 AND s.shop_id = $2
        GROUP BY s.seller_id, u.username
        ORDER BY total_revenue DESC`

	rows, err := r.db.Query(ctx, query, companyID, shopID, from, to)
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
