package http

import (
	"context"
	"strconv"

	"github.com/gin-gonic/gin"
)

func (h *Handler) getAnalyticsSummary(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	shopID := c.MustGet("shop_id").(int)
	period := c.DefaultQuery("period", "today")
	summary, err := h.saleRepo.GetPeriodSummary(context.Background(), companyID, shopID, period)
	if err != nil {
		logErr(c, err, "Ошибка получения сводки аналитики", "company_id", companyID, "period", period)
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
	products, err := h.saleRepo.GetTopProductsDetailed(context.Background(), companyID, shopID, limit)
	if err != nil {
		logErr(c, err, "Ошибка получения топа товаров", "company_id", companyID, "limit", limit)
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
	stats, err := h.saleRepo.GetSellerStats(context.Background(), companyID, shopID)
	if err != nil {
		logErr(c, err, "Ошибка получения статистики продавцов", "company_id", companyID)
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}
	c.JSON(200, stats)
}
