package http

import (
	"context"
	"log"
	"net/http"
	"os"
	"retail-managment-system/internal/auth"
	"retail-managment-system/internal/domain"
	"strconv"

	"github.com/gin-gonic/gin"
)

// getAllUsers — список сотрудников текущей компании
func (h *Handler) getAllUsers(c *gin.Context) {
	companyID, _ := c.Get("company_id")
	list, err := h.userRepo.GetAllByCompany(context.Background(), companyID.(int))
	if err != nil {
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}
	c.JSON(200, list)
}

// createUser — создание сотрудника.
// Для seller'ов пароль не требуется — они входят только через PIN.
func (h *Handler) createUser(c *gin.Context) {
	var req domain.CreateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	ownerCompanyID, exists := c.Get("company_id")
	log.Println(ownerCompanyID)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Компания создателя не определена"})
		return
	}

	user := domain.User{
		Username:  req.Username,
		Role:      req.Role,
		CompanyID: ownerCompanyID.(int),
	}

	// Для seller'а — пароль не нужен, только PIN
	if req.Role == "seller" {
		if req.Pin == "" {
			c.JSON(400, gin.H{"error": "PIN обязателен для продавца (4 цифры)"})
			return
		}
		if len(req.Pin) != 4 {
			c.JSON(400, gin.H{"error": "PIN должен быть 4 цифры"})
			return
		}
		pinHash, err := auth.HashPassword(req.Pin)
		if err != nil {
			c.JSON(500, gin.H{"error": "Ошибка хэширования PIN"})
			return
		}
		user.PinHash = pinHash
		if err := h.userRepo.CreateSeller(context.Background(), user); err != nil {
			c.JSON(500, gin.H{"error": "Ошибка создания продавца"})
			return
		}
	} else {
		// Для owner (или других ролей) — пароль обязателен
		if req.Password == "" {
			c.JSON(400, gin.H{"error": "Пароль обязателен"})
			return
		}
		hash, _ := auth.HashPassword(req.Password)
		user.PasswordHash = hash

		if req.Pin != "" {
			if len(req.Pin) != 4 {
				c.JSON(400, gin.H{"error": "PIN должен быть 4 цифры"})
				return
			}
			pinHash, err := auth.HashPassword(req.Pin)
			if err != nil {
				c.JSON(500, gin.H{"error": "Ошибка хэширования PIN"})
				return
			}
			user.PinHash = pinHash
			if err := h.userRepo.CreateWithPin(context.Background(), user); err != nil {
				c.JSON(500, gin.H{"error": "Ошибка создания пользователя"})
				return
			}
		} else {
			if err := h.userRepo.Create(context.Background(), user); err != nil {
				c.JSON(500, gin.H{"error": "Ошибка создания пользователя"})
				return
			}
		}
	}

	c.JSON(200, gin.H{"status": "ok"})
}

// deleteUser — удаление сотрудника.
// ИСПРАВЛЕНО (IDOR): раньше удаление шло по глобальному id без проверки
// company_id — владелец одной компании мог удалить сотрудника другой
// компании, подобрав числовой id.
func (h *Handler) deleteUser(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	id, _ := strconv.Atoi(c.Param("id"))
	if err := h.userRepo.Delete(context.Background(), id, companyID); err != nil {
		c.JSON(500, gin.H{"error": "Ошибка удаления"})
		return
	}
	c.JSON(200, gin.H{"status": "ok"})
}

// setUserPin — хозяин устанавливает или меняет PIN сотрудника
func (h *Handler) setUserPin(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(400, gin.H{"error": "Неверный ID"})
		return
	}

	var req domain.SetPinRequest
	if err := c.ShouldBindJSON(&req); err != nil || len(req.Pin) != 4 {
		c.JSON(400, gin.H{"error": "PIN должен быть 4 цифры"})
		return
	}

	companyID, _ := c.Get("company_id")
	_, err = h.userRepo.GetByIDAndCompany(context.Background(), id, companyID.(int))
	if err != nil {
		c.JSON(404, gin.H{"error": "Пользователь не найден"})
		return
	}

	pinHash, err := auth.HashPassword(req.Pin)
	if err != nil {
		c.JSON(500, gin.H{"error": "Ошибка хэширования"})
		return
	}

	if err := h.userRepo.SetPin(context.Background(), id, companyID.(int), pinHash); err != nil {
		c.JSON(500, gin.H{"error": "Ошибка сохранения PIN"})
		return
	}

	c.JSON(200, gin.H{"status": "ok"})
}

// pinLogin — вход продавца через PIN в режиме терминала.
// ИСПРАВЛЕНО: теперь PIN проверяется в паре с company_id (через
// GetByIDAndCompany), а не по голому user_id — иначе подбор 4-значного
// PIN мог сработать против пользователя любой другой компании.
func (h *Handler) pinLogin(c *gin.Context) {
	var req domain.PinLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Неверные данные"})
		return
	}

	user, err := h.userRepo.GetByIDAndCompany(context.Background(), req.UserID, req.CompanyID)
	if err != nil || user.PinHash == "" {
		c.JSON(401, gin.H{"error": "PIN не установлен"})
		return
	}

	if !auth.CheckPasswordHash(req.Pin, user.PinHash) {
		c.JSON(401, gin.H{"error": "Неверный PIN"})
		return
	}

	token, errToken := auth.GenerateToken(user.ID, user.CompanyID, user.Role, os.Getenv("JWT_SECRET"))
	if errToken != nil {
		log.Println("Ошибка генерации JWT:", errToken)
		c.JSON(500, gin.H{"error": "Ошибка сервера"})
		return
	}

	c.JSON(200, gin.H{
		"token":    token,
		"role":     user.Role,
		"username": user.Username,
	})
}

// getTerminalUsers — публичный эндпоинт: список пользователей компании для терминального режима.
func (h *Handler) getTerminalUsers(c *gin.Context) {
	companyIDStr := c.Query("company_id")
	companyID, err := strconv.Atoi(companyIDStr)
	if err != nil || companyID == 0 {
		c.JSON(400, gin.H{"error": "company_id обязателен"})
		return
	}

	list, err := h.userRepo.GetAllByCompany(context.Background(), companyID)
	if err != nil {
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}

	type safeUser struct {
		ID       int    `json:"id"`
		Username string `json:"username"`
		Role     string `json:"role"`
		HasPin   bool   `json:"has_pin"`
	}
	safe := make([]safeUser, 0, len(list))
	for _, u := range list {
		// В терминальном режиме показываем только seller'ов с PIN
		if u.Role == "seller" && u.HasPin {
			safe = append(safe, safeUser{
				ID:       u.ID,
				Username: u.Username,
				Role:     u.Role,
				HasPin:   u.HasPin,
			})
		}
	}
	c.JSON(200, safe)
}

// generateTgLinkToken — хозяин запрашивает токен для привязки Telegram
func (h *Handler) generateTgLinkToken(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Не авторизован"})
		return
	}

	token, err := h.userRepo.GenerateTgLinkToken(context.Background(), userID.(int))
	if err != nil {
		c.JSON(500, gin.H{"error": "Ошибка генерации токена"})
		return
	}

	botName := os.Getenv("TELEGRAM_BOT_NAME")
	c.JSON(200, domain.TgLinkTokenResponse{
		Token:   token,
		BotName: botName,
	})
}

// unlinkTelegram — отвязать Telegram от аккаунта владельца
func (h *Handler) unlinkTelegram(c *gin.Context) {
	userID, _ := c.Get("user_id")
	if err := h.userRepo.InvalidateTgLink(context.Background(), userID.(int)); err != nil {
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}
	c.JSON(200, gin.H{"status": "ok"})
}
