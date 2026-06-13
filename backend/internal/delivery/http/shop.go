package http

import (
	"context"
	"net/http"
	"retail-managment-system/internal/domain"
	"strconv"

	"github.com/gin-gonic/gin"
)

// getShops — список магазинов текущей компании
func (h *Handler) getShops(c *gin.Context) {
	companyID, _ := c.Get("company_id")
	shops, err := h.shopRepo.GetAllByCompany(context.Background(), companyID.(int))
	if err != nil {
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}
	if shops == nil {
		shops = []domain.Shop{}
	}
	c.JSON(200, shops)
}

// createShop — создать новый магазин
func (h *Handler) createShop(c *gin.Context) {
	var req domain.CreateShopRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Укажите название магазина"})
		return
	}
	companyID, _ := c.Get("company_id")
	shop, err := h.shopRepo.Create(context.Background(), companyID.(int), req.Name)
	if err != nil {
		c.JSON(500, gin.H{"error": "Ошибка создания магазина"})
		return
	}
	c.JSON(http.StatusCreated, shop)
}

// updateShop — переименовать магазин
func (h *Handler) updateShop(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	var req domain.CreateShopRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Укажите название"})
		return
	}
	companyID, _ := c.Get("company_id")
	if err := h.shopRepo.Update(context.Background(), id, companyID.(int), req.Name); err != nil {
		c.JSON(500, gin.H{"error": "Ошибка обновления"})
		return
	}
	c.JSON(200, gin.H{"status": "ok"})
}

// deleteShop — удалить магазин
func (h *Handler) deleteShop(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	companyID, _ := c.Get("company_id")
	if err := h.shopRepo.Delete(context.Background(), id, companyID.(int)); err != nil {
		c.JSON(500, gin.H{"error": "Ошибка удаления"})
		return
	}
	c.JSON(200, gin.H{"status": "ok"})
}
