package http

import (
	"context"
	"strconv"

	"github.com/gin-gonic/gin"
)

func (h *Handler) getAnalyticsSummary(c *gin.Context) {
	period := c.DefaultQuery("period", "today")
	summary, err := h.saleRepo.GetPeriodSummary(context.Background(), period)
	if err != nil {
		c.JSON(500, gin.H{"error": "Ошибка получения данных"})
		return
	}
	c.JSON(200, summary)
}
func (h *Handler) getTopProducts(c *gin.Context) {
	limitStr := c.DefaultQuery("limit", "10")
	limit, _ := strconv.Atoi(limitStr)
	products, err := h.saleRepo.GetTopProductsDetailed(context.Background(), limit)
	if err != nil {
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}
	c.JSON(200, products)
}
func (h *Handler) getSalesByDay(c *gin.Context) {
	days, _ := strconv.Atoi(c.DefaultQuery("days", "7"))
	data, err := h.saleRepo.GetSalesByDay(context.Background(), days)
	if err != nil {
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}
	c.JSON(200, data)
}
func (h *Handler) getLowStock(c *gin.Context) {
	threshold, _ := strconv.Atoi(c.DefaultQuery("threshold", "10"))
	products, err := h.productRepo.GetLowStockProducts(context.Background(), threshold)
	if err != nil {
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}
	c.JSON(200, products)
}
func (h *Handler) getSellerStats(c *gin.Context) {
	stats, err := h.saleRepo.GetSellerStats(context.Background())
	if err != nil {
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}
	c.JSON(200, stats)
}
