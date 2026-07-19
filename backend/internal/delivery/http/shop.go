package http

import (
	"context"
	"net/http"
	"os"
	"retail-managment-system/internal/auth"
	"retail-managment-system/internal/domain"
	"strconv"

	"github.com/gin-gonic/gin"
)

// getShops — список магазинов текущей компании
func (h *Handler) getShops(c *gin.Context) {
	companyID, _ := c.Get("company_id")
	shops, err := h.shopRepo.GetAllByCompany(context.Background(), companyID.(int))
	if err != nil {
		logErr(c, err, "Ошибка получения списка магазинов", "company_id", companyID)
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}
	if shops == nil {
		shops = []domain.Shop{}
	}
	c.JSON(200, shops)
}

// createShop — создать новый магазин.
// Только что созданный магазин сразу становится активным для владельца
// (логично: он его для того и создавал) — поэтому в ответе также приходит
// новый JWT с этим shop_id, которым фронтенд сразу заменяет старый токен.
func (h *Handler) createShop(c *gin.Context) {
	var req domain.CreateShopRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		logWarn(c, "Создание магазина: неверный формат запроса", "error", err.Error())
		c.JSON(400, gin.H{"error": "Укажите название магазина"})
		return
	}
	companyID := c.MustGet("company_id").(int)
	userID := c.MustGet("user_id").(int)
	role := c.MustGet("role").(string)

	shop, err := h.shopRepo.Create(context.Background(), companyID, req.Name)
	if err != nil {
		logErr(c, err, "Ошибка создания магазина", "company_id", companyID, "name", req.Name)
		c.JSON(500, gin.H{"error": "Ошибка создания магазина"})
		return
	}

	if err := h.userRepo.SetCurrentShop(context.Background(), userID, shop.ID); err != nil {
		logErr(c, err, "Создание магазина: не удалось выбрать его активным", "user_id", userID, "shop_id", shop.ID)
	}

	token, errToken := auth.GenerateToken(userID, companyID, shop.ID, role, os.Getenv("JWT_SECRET"))
	if errToken != nil {
		logErr(c, errToken, "Создание магазина: ошибка генерации токена", "user_id", userID, "shop_id", shop.ID)
		c.JSON(500, gin.H{"error": "Ошибка сервера"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"id":         shop.ID,
		"company_id": shop.CompanyID,
		"name":       shop.Name,
		"token":      token,
		"shop_id":    shop.ID,
	})
}

// updateShop — переименовать магазин
func (h *Handler) updateShop(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	var req domain.CreateShopRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		logWarn(c, "Обновление магазина: неверный формат запроса", "shop_id", id, "error", err.Error())
		c.JSON(400, gin.H{"error": "Укажите название"})
		return
	}
	companyID, _ := c.Get("company_id")
	if err := h.shopRepo.Update(context.Background(), id, companyID.(int), req.Name); err != nil {
		logErr(c, err, "Ошибка обновления магазина", "shop_id", id, "company_id", companyID, "name", req.Name)
		c.JSON(500, gin.H{"error": "Ошибка обновления"})
		return
	}
	c.JSON(200, gin.H{"status": "ok"})
}

// switchShop — POST /api/shops/:id/switch — владелец переключается на другой
// свой магазин. Проверяет, что магазин принадлежит его компании, запоминает
// выбор (чтобы при следующем входе открылся тот же магазин) и выдаёт новый
// JWT с этим shop_id — все дальнейшие запросы (товары, продажи, склад,
// должники, аналитика) автоматически будут в рамках выбранного магазина.
func (h *Handler) switchShop(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Неверный ID магазина"})
		return
	}
	companyID := c.MustGet("company_id").(int)
	userID := c.MustGet("user_id").(int)

	shops, err := h.shopRepo.GetAllByCompany(context.Background(), companyID)
	if err != nil {
		logErr(c, err, "Переключение магазина: ошибка получения списка магазинов", "company_id", companyID)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Ошибка"})
		return
	}
	var target *domain.Shop
	for i := range shops {
		if shops[i].ID == id {
			target = &shops[i]
			break
		}
	}
	if target == nil {
		logWarn(c, "Переключение магазина: магазин не найден или чужой", "shop_id", id, "company_id", companyID)
		c.JSON(http.StatusNotFound, gin.H{"error": "Магазин не найден"})
		return
	}

	if err := h.userRepo.SetCurrentShop(context.Background(), userID, target.ID); err != nil {
		logErr(c, err, "Переключение магазина: не удалось сохранить выбор", "user_id", userID, "shop_id", target.ID)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Ошибка сохранения"})
		return
	}

	role := c.MustGet("role").(string)
	token, err := auth.GenerateToken(userID, companyID, target.ID, role, os.Getenv("JWT_SECRET"))
	if err != nil {
		logErr(c, err, "Переключение магазина: ошибка генерации токена", "user_id", userID, "shop_id", target.ID)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Ошибка сервера"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"token":   token,
		"shop_id": target.ID,
		"shop":    target,
	})
}

// deleteShop — удалить магазин
func (h *Handler) deleteShop(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	companyID, _ := c.Get("company_id")
	if err := h.shopRepo.Delete(context.Background(), id, companyID.(int)); err != nil {
		logErr(c, err, "Ошибка удаления магазина", "shop_id", id, "company_id", companyID)
		c.JSON(500, gin.H{"error": "Ошибка удаления"})
		return
	}
	c.JSON(200, gin.H{"status": "ok"})
}
