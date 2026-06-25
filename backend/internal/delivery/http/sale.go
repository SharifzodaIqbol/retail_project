package http

import (
	"context"
	"log"
	"retail-managment-system/internal/domain"
	"strconv"

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
	companyID := c.MustGet("company_id").(int)
	sellerID := c.MustGet("user_id").(int)
	saleID, lowStockItems, err := h.saleRepo.ExecuteSale(context.Background(), companyID, sellerID, input.Items, input.Total)
	log.Println(err)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}

	go func() {
		ownerID, _ := h.userRepo.GetOwnerChatID(context.Background(), companyID)
		if ownerID != 0 {
			for _, item := range lowStockItems {
				h.tgBot.SendLowStockAlert(ownerID, item.Name, int(item.Stock))
			}
		}
	}()

	c.JSON(200, gin.H{"id": saleID})
}

// getSalesHistory — ИСПРАВЛЕНО: раньше возвращалась история ВСЕХ компаний
// без какой-либо фильтрации. Теперь строго по company_id текущего владельца.
func (h *Handler) getSalesHistory(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	history, _ := h.saleRepo.GetAll(context.Background(), companyID)
	c.JSON(200, history)
}

// cancelSale — ИСПРАВЛЕНО: раньше чек искался и отменялся по глобальному id
// без проверки company_id, поэтому владелец одной компании мог отменить
// (и тем самым изменить остатки на складе) чужой чек, просто подобрав id.
func (h *Handler) cancelSale(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	idStr := c.Param("id")
	id, _ := strconv.Atoi(idStr)
	var input struct {
		Reason string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(400, gin.H{"error": "Неверный формат данных"})
		return
	}
	log.Printf("[DEBUG] Начинаем отмену чека ID: %v (company_id=%v)", id, companyID)

	totalAmount, err := h.saleRepo.GetSaleTotal(context.Background(), companyID, id)
	if err != nil {
		log.Printf("[ERROR]: %v", err)
		c.JSON(404, gin.H{"error": "Чек не найден"})
		return
	}

	if err = h.saleRepo.CancelSale(context.Background(), companyID, id, input.Reason); err != nil {
		log.Printf("[ERROR]: %v", err)
		c.JSON(500, gin.H{"error": "Не удалось отменить чек: " + err.Error()})
		return
	}

	go func() {
		ownerID, _ := h.userRepo.GetOwnerChatID(context.Background(), companyID)
		if ownerID != 0 {
			h.tgBot.SendCancelNotification(ownerID, id, input.Reason, totalAmount)
		}
	}()

	c.JSON(200, gin.H{"status": "ok"})
}
