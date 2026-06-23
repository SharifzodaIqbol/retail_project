package http

import (
	"context"
	"net/http"
	"retail-managment-system/internal/domain"
	"retail-managment-system/internal/repository"
	"strconv"
	"strings"

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

// searchProducts — поиск по названию для автодополнения в кассе.
// ИСПРАВЛЕНО: раньше читался параметр "name", а Flutter всегда шлёт "q" —
// поэтому поиск по названию всегда возвращал пустой список.
// Также добавлен фильтр по company_id (раньше товары не фильтровались по компании).
func (h *Handler) searchProducts(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	name := strings.TrimSpace(c.Query("q"))
	if name == "" {
		c.JSON(http.StatusOK, []domain.Product{})
		return
	}

	products, err := h.productRepo.SearchByName(context.Background(), companyID, name)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Ошибка поиска"})
		return
	}
	c.JSON(http.StatusOK, products)
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

// updateInventory — обновление склада.
// НОВОЕ: если изменение делает продавец (role == "seller"), причина обязательна.
// Склад обновляется сразу, владельцу уходит Telegram-уведомление постфактум.
func (h *Handler) updateInventory(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	role, _ := c.Get("role")
	companyID := c.MustGet("company_id").(int)
	userID, _ := c.Get("user_id")

	var input struct {
		AddStock  int     `json:"add_stock"`
		SellPrice float64 `json:"sell_price"`
		BuyPrice  float64 `json:"buy_price"`
		Reason    string  `json:"reason"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(400, gin.H{"error": "Неверный формат данных"})
		return
	}

	isSeller := role == "seller"
	if isSeller && strings.TrimSpace(input.Reason) == "" {
		c.JSON(400, gin.H{"error": "Укажите причину изменения склада"})
		return
	}

	if err := h.productRepo.UpdateInventory(context.Background(), id, companyID, input.AddStock, input.SellPrice, input.BuyPrice); err != nil {
		if err == repository.ErrNotFound {
			c.JSON(404, gin.H{"error": "Товар не найден"})
			return
		}
		c.JSON(500, gin.H{"error": "Не удалось обновить склад"})
		return
	}

	if isSeller && h.tgBot != nil {
		go func() {
			ctx := context.Background()
			productName, err := h.productRepo.GetNameByID(ctx, id, companyID)
			if err != nil {
				return
			}
			ownerChatID, err := h.userRepo.GetOwnerChatID(ctx, companyID)
			if err != nil || ownerChatID == 0 {
				return
			}
			seller, _ := h.userRepo.GetByID(ctx, userID.(int))
			h.tgBot.SendInventoryChangeNotification(ownerChatID, seller.Username, productName, input.AddStock, input.Reason)
		}()
	}

	c.JSON(200, gin.H{"status": "ok"})
}

func (h *Handler) deleteProduct(c *gin.Context) {
	role := c.MustGet("role").(string)
	if role != "owner" {
		c.JSON(403, gin.H{"error": "Нет прав"})
		return
	}
	companyID := c.MustGet("company_id").(int)
	id, _ := strconv.Atoi(c.Param("id"))
	if err := h.productRepo.SoftDelete(context.Background(), id, companyID); err != nil {
		if err == repository.ErrNotFound {
			c.JSON(404, gin.H{"error": "Товар не найден"})
			return
		}
		c.JSON(500, gin.H{"error": "Ошибка удаления"})
		return
	}
	c.JSON(200, gin.H{"status": "ok"})
}
