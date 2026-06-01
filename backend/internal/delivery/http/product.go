package http

import (
	"context"
	"net/http"
	"retail-managment-system/internal/domain"
	"strconv"

	"github.com/gin-gonic/gin"
)

func (h *Handler) getProductByBarcode(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	barcode := c.Param("barcode")

	p, err := h.productRepo.GetByBarcode(context.Background(), companyID, barcode)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Товар не найден"})
		return
	}
	c.JSON(http.StatusOK, p)
}
func (h *Handler) searchProducts(c *gin.Context) {
	name := c.Query("name")
	products, _ := h.productRepo.SearchByName(context.Background(), name)
	c.JSON(200, products)
}
func (h *Handler) getAllProducts(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	products, err := h.productRepo.GetAll(context.Background(), companyID)
	if err != nil {
		c.JSON(500, gin.H{"error": "Ошибка получения товаров"})
		return
	}
	c.JSON(200, products)
}
func (h *Handler) createProduct(c *gin.Context) {
	var p domain.Product
	if err := c.ShouldBindJSON(&p); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}
	p.CompanyID = c.MustGet("company_id").(int)
	if err := h.productRepo.Create(context.Background(), p); err != nil {
		c.JSON(500, gin.H{"error": "Ошибка создания товара"})
		return
	}
	c.JSON(200, gin.H{"status": "ok"})
}
func (h *Handler) updateInventory(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	var input struct {
		AddStock  int     `json:"add_stock"`
		SellPrice float64 `json:"sell_price"`
		BuyPrice  float64 `json:"buy_price"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(400, gin.H{"error": "Неверный формат данных"})
		return
	}
	if err := h.productRepo.UpdateInventory(context.Background(), id, input.AddStock, input.SellPrice, input.BuyPrice); err != nil {
		c.JSON(500, gin.H{"error": "Не удалось обновить склад"})
		return
	}
	c.JSON(200, gin.H{"status": "ok"})
}
func (h *Handler) deleteProduct(c *gin.Context) {
	role := c.MustGet("role").(string)
	if role != "owner" {
		c.JSON(403, gin.H{"error": "Нет прав"})
		return
	}
	id, _ := strconv.Atoi(c.Param("id"))
	if err := h.productRepo.SoftDelete(context.Background(), id); err != nil {
		c.JSON(500, gin.H{"error": "Ошибка удаления"})
		return
	}
	c.JSON(200, gin.H{"status": "ok"})
}
