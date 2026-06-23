package http

import (
	"context"
	"log"
	"strconv"

	"github.com/gin-gonic/gin"
)

// ВСЕ методы ниже ИСПРАВЛЕНЫ: раньше аналитика (выручка, топ товаров, продажи
// по дням, низкий остаток, статистика продавцов) считалась по ВСЕМ компаниям
// в системе сразу — то есть владелец одной компании видел суммарную выручку,
// чеки и склад всех остальных компаний. Теперь все запросы строго
// ограничены company_id текущего владельца.

func (h *Handler) getAnalyticsSummary(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	period := c.DefaultQuery("period", "today")
	summary, err := h.saleRepo.GetPeriodSummary(context.Background(), companyID, period)
	if err != nil {
		c.JSON(500, gin.H{"error": "Ошибка получения данных"})
		return
	}
	c.JSON(200, summary)
}

func (h *Handler) getTopProducts(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	limitStr := c.DefaultQuery("limit", "10")
	limit, _ := strconv.Atoi(limitStr)
	products, err := h.saleRepo.GetTopProductsDetailed(context.Background(), companyID, limit)
	if err != nil {
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}
	c.JSON(200, products)
}

func (h *Handler) getSalesByDay(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	days, _ := strconv.Atoi(c.DefaultQuery("days", "7"))
	data, err := h.saleRepo.GetSalesByDay(context.Background(), companyID, days)
	if err != nil {
		log.Printf("[ERROR] Failed to get sales by day: %v", err)
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
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}
	c.JSON(200, products)
}

func (h *Handler) getSellerStats(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	stats, err := h.saleRepo.GetSellerStats(context.Background(), companyID)
	if err != nil {
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}
	c.JSON(200, stats)
}
