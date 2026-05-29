package http

import (
	"context"
	"retail-managment-system/internal/domain"

	"github.com/gin-gonic/gin"
)

func (h *Handler) executeSale(c *gin.Context) {
	var input struct {
		Items []domain.SaleItem `json:"items"`
		Total float64           `json:"total_amount"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}
	sellerID := c.MustGet("user_id").(int)
	saleID, lowStockItems, err := h.saleRepo.ExecuteSale(context.Background(), sellerID, input.Items, input.Total)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}

	go func() {
		ownerID, _ := h.userRepo.GetOwnerChatID(context.Background())
		if ownerID != 0 {
			for _, item := range lowStockItems {
				h.tgBot.SendLowStockAlert(ownerID, item.Name, item.Stock)
			}
		}
	}()

	c.JSON(200, gin.H{"id": saleID})
}
func (h *Handler) getSalesHistory(c *gin.Context) {
	history, _ := h.saleRepo.GetAll(context.Background())
	c.JSON(200, history)
}
func (h *Handler) cancelSale(c *gin.Context) {
	var input struct {
		SaleID int    `json:"sale_id"`
		Reason string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(400, gin.H{"error": "Неверный формат данных"})
		return
	}

	var totalAmount float64
	err := h.dbPool.QueryRow(context.Background(), "SELECT total_amount FROM sales WHERE id = $1", input.SaleID).Scan(&totalAmount)
	if err != nil {
		c.JSON(404, gin.H{"error": "Чек не найден"})
		return
	}

	if err = h.saleRepo.CancelSale(context.Background(), input.SaleID, input.Reason); err != nil {
		c.JSON(500, gin.H{"error": "Не удалось отменить чек: " + err.Error()})
		return
	}

	go func() {
		ownerID, _ := h.userRepo.GetOwnerChatID(context.Background())
		if ownerID != 0 {
			h.tgBot.SendCancelNotification(ownerID, input.SaleID, input.Reason, totalAmount)
		}
	}()

	c.JSON(200, gin.H{"status": "ok"})
}
