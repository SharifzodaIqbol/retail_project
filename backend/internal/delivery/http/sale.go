package http

import (
	"context"
	"net/http"
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
		logWarn(c, "Оформление продажи: неверный формат запроса", "error", err.Error())
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}
	companyID := c.MustGet("company_id").(int)
	shopID := c.MustGet("shop_id").(int)
	sellerID := c.MustGet("user_id").(int)
	saleID, lowStockItems, err := h.saleRepo.ExecuteSale(context.Background(), companyID, shopID, sellerID, input.Items, input.Total)
	if err != nil {
		logErr(c, err, "Ошибка оформления продажи", "company_id", companyID, "seller_id", sellerID, "items_count", len(input.Items), "total", input.Total)
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}

	go func() {
		ownerID, _ := h.userRepo.GetOwnerChatID(context.Background(), companyID)
		if ownerID != 0 {
			for _, item := range lowStockItems {
				h.tgBot.SendLowStockAlert(ownerID, item.Name, item.Stock, item.Unit)
			}
		}
	}()

	c.JSON(200, gin.H{"id": saleID})
}

// getSalesHistory — GET /api/sales?page=1&limit=50
// Возвращает страницу истории продаж. Параметры: page (с 1), limit (макс. 200).
func (h *Handler) getSalesHistory(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	shopID := c.MustGet("shop_id").(int)

	page, limit := parsePagination(c, 50, 200)
	offset := (page - 1) * limit

	history, total, err := h.saleRepo.GetAll(context.Background(), companyID, shopID, limit, offset)
	if err != nil {
		logErr(c, err, "Ошибка получения истории продаж", "company_id", companyID)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Ошибка получения истории продаж"})
		return
	}
	c.JSON(http.StatusOK, buildPage(history, total, page, limit))
}

// cancelSale — ИСПРАВЛЕНО: раньше чек искался и отменялся по глобальному id
// без проверки company_id, поэтому владелец одной компании мог отменить
// (и тем самым изменить остатки на складе) чужой чек, просто подобрав id.
func (h *Handler) cancelSale(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	shopID := c.MustGet("shop_id").(int)
	idStr := c.Param("id")
	id, _ := strconv.Atoi(idStr)
	var input struct {
		Reason string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		logWarn(c, "Отмена продажи: неверный формат запроса", "sale_id", id, "error", err.Error())
		c.JSON(400, gin.H{"error": "Неверный формат данных"})
		return
	}

	totalAmount, err := h.saleRepo.GetSaleTotal(context.Background(), companyID, shopID, id)
	if err != nil {
		logWarn(c, "Отмена продажи: чек не найден", "sale_id", id, "company_id", companyID, "error", err.Error())
		c.JSON(404, gin.H{"error": "Чек не найден"})
		return
	}

	if err = h.saleRepo.CancelSale(context.Background(), companyID, shopID, id, input.Reason); err != nil {
		logErr(c, err, "Ошибка отмены продажи", "sale_id", id, "company_id", companyID, "reason", input.Reason)
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
