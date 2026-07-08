package http

import (
	"context"
	"strconv"

	"github.com/gin-gonic/gin"
)

// parseShopIDFilter читает опциональный query-параметр ?shop_id=, который
// позволяет владельцу переключаться между магазинами в аналитике. Пустое
// значение (или его отсутствие) означает "все магазины компании вместе",
// как было раньше.
func parseShopIDFilter(c *gin.Context) *int {
	raw := c.Query("shop_id")
	if raw == "" {
		return nil
	}
	v, err := strconv.Atoi(raw)
	if err != nil {
		return nil
	}
	return &v
}

func (h *Handler) getAnalyticsSummary(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	period := c.DefaultQuery("period", "today")
	shopID := parseShopIDFilter(c)
	summary, err := h.saleRepo.GetPeriodSummary(context.Background(), companyID, period, shopID)
	if err != nil {
		logErr(c, err, "Ошибка получения сводки аналитики", "company_id", companyID, "period", period)
		c.JSON(500, gin.H{"error": "Ошибка получения данных"})
		return
	}
	c.JSON(200, summary)
}

func (h *Handler) getTopProducts(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	limitStr := c.DefaultQuery("limit", "10")
	limit, _ := strconv.Atoi(limitStr)
	shopID := parseShopIDFilter(c)
	products, err := h.saleRepo.GetTopProductsDetailed(context.Background(), companyID, limit, shopID)
	if err != nil {
		logErr(c, err, "Ошибка получения топа товаров", "company_id", companyID, "limit", limit)
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}
	c.JSON(200, products)
}

func (h *Handler) getSalesByDay(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	days, _ := strconv.Atoi(c.DefaultQuery("days", "7"))
	shopID := parseShopIDFilter(c)
	data, err := h.saleRepo.GetSalesByDay(context.Background(), companyID, days, shopID)
	if err != nil {
		logErr(c, err, "Ошибка получения продаж по дням", "company_id", companyID, "days", days)
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}
	c.JSON(200, data)
}

func (h *Handler) getLowStock(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	threshold, _ := strconv.Atoi(c.DefaultQuery("threshold", "10"))
	products, err := h.productRepo.GetLowStockProducts(context.Background(), companyID, threshold)
	if err != nil {
		logErr(c, err, "Ошибка получения товаров с низким остатком", "company_id", companyID, "threshold", threshold)
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}
	c.JSON(200, products)
}

func (h *Handler) getSellerStats(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	shopID := parseShopIDFilter(c)
	stats, err := h.saleRepo.GetSellerStats(context.Background(), companyID, shopID)
	if err != nil {
		logErr(c, err, "Ошибка получения статистики продавцов", "company_id", companyID)
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}
	c.JSON(200, stats)
}

// getShopsSummary — сводка по каждому магазину компании за период (задача:
// многомагазинная аналитика). Владелец видит все свои магазины одним
// списком — выручку, прибыль, число чеков и средний чек по каждому.
func (h *Handler) getShopsSummary(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	period := c.DefaultQuery("period", "today")
	summary, err := h.saleRepo.GetSummaryByShop(context.Background(), companyID, period)
	if err != nil {
		logErr(c, err, "Ошибка получения сводки по магазинам", "company_id", companyID, "period", period)
		c.JSON(500, gin.H{"error": "Ошибка получения данных"})
		return
	}
	c.JSON(200, summary)
}
