package http

import (
	"context"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
)

// resolvePeriod вычисляет [from, to) для аналитики: либо готовый период
// (today/week/month), либо произвольный диапазон дат, переданный
// владельцем через from/to (формат YYYY-MM-DD, конец дня включительно).
func resolvePeriod(c *gin.Context) (from, to time.Time) {
	period := c.DefaultQuery("period", "today")
	now := time.Now()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())

	switch period {
	case "week":
		return today.AddDate(0, 0, -6), today.AddDate(0, 0, 1)
	case "month":
		return time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location()), today.AddDate(0, 0, 1)
	case "custom":
		fromStr := c.Query("from")
		toStr := c.Query("to")
		f, errF := time.ParseInLocation("2006-01-02", fromStr, now.Location())
		t, errT := time.ParseInLocation("2006-01-02", toStr, now.Location())
		if errF != nil || errT != nil {
			// Некорректный диапазон — безопасный откат на "сегодня"
			return today, today.AddDate(0, 0, 1)
		}
		return f, t.AddDate(0, 0, 1)
	default: // today
		return today, today.AddDate(0, 0, 1)
	}
}

func (h *Handler) getAnalyticsSummary(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	shopID := c.MustGet("shop_id").(int)
	from, to := resolvePeriod(c)
	summary, err := h.saleRepo.GetPeriodSummary(context.Background(), companyID, shopID, from, to)
	if err != nil {
		logErr(c, err, "Ошибка получения сводки аналитики", "company_id", companyID, "from", from, "to", to)
		c.JSON(500, gin.H{"error": "Ошибка получения данных"})
		return
	}
	c.JSON(200, summary)
}

func (h *Handler) getTopProducts(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	shopID := c.MustGet("shop_id").(int)
	limitStr := c.DefaultQuery("limit", "10")
	limit, _ := strconv.Atoi(limitStr)
	from, to := resolvePeriod(c)
	products, err := h.saleRepo.GetTopProductsDetailed(context.Background(), companyID, shopID, from, to, limit)
	if err != nil {
		logErr(c, err, "Ошибка получения топа товаров", "company_id", companyID, "limit", limit, "from", from, "to", to)
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}
	c.JSON(200, products)
}

func (h *Handler) getSalesByDay(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	shopID := c.MustGet("shop_id").(int)
	days, _ := strconv.Atoi(c.DefaultQuery("days", "7"))
	data, err := h.saleRepo.GetSalesByDay(context.Background(), companyID, shopID, days)
	if err != nil {
		logErr(c, err, "Ошибка получения продаж по дням", "company_id", companyID, "days", days)
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}
	c.JSON(200, data)
}

func (h *Handler) getLowStock(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	shopID := c.MustGet("shop_id").(int)
	threshold, _ := strconv.Atoi(c.DefaultQuery("threshold", "10"))
	products, err := h.productRepo.GetLowStockProducts(context.Background(), companyID, shopID, threshold)
	if err != nil {
		logErr(c, err, "Ошибка получения товаров с низким остатком", "company_id", companyID, "threshold", threshold)
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}
	c.JSON(200, products)
}

func (h *Handler) getSellerStats(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	shopID := c.MustGet("shop_id").(int)
	from, to := resolvePeriod(c)
	stats, err := h.saleRepo.GetSellerStats(context.Background(), companyID, shopID, from, to)
	if err != nil {
		logErr(c, err, "Ошибка получения статистики продавцов", "company_id", companyID, "from", from, "to", to)
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}
	c.JSON(200, stats)
}
