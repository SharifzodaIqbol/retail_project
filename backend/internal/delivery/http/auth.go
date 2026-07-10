package http

import (
	"context"
	"errors"
	"net/http"
	"os"
	"retail-managment-system/internal/auth"
	"retail-managment-system/internal/domain"
	"retail-managment-system/internal/repository"
	"strings"

	"github.com/gin-gonic/gin"
)

func (h *Handler) register(c *gin.Context) {
	var req domain.RegisterCompanyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	hash, err := auth.HashPassword(req.Password)
	if err != nil {
		logErr(c, err, "Регистрация: ошибка хэширования пароля")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Ошибка шифрования"})
		return
	}

	err = h.companyRepo.RegisterNewBusiness(
		context.Background(),
		req.CompanyName, req.Username, hash,
		req.DeviceID, req.Phone,
	)
	if err != nil {
		// Проверяем тип ошибки — если это фрод, возвращаем 409
		var trialErr *repository.TrialNotAllowedError
		if errors.As(err, &trialErr) {
			logWarn(c, "Регистрация отклонена: повторное использование пробного периода",
				"reason", trialErr.Reason, "username", req.Username, "device_id", req.DeviceID)
			c.JSON(http.StatusConflict, gin.H{
				"error":  "trial_not_allowed",
				"reason": trialErr.Reason,
				// Не говорим "устройство найдено" — просто предлагаем купить
				"message": "Пробный период для этого устройства уже был использован. Свяжитесь с нами для подключения.",
			})
			return
		}
		logErr(c, err, "Ошибка регистрации компании", "username", req.Username)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Логин занят или ошибка БД"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"status": "success"})
}

// login — вход владельца по username+password.
// ИСПРАВЛЕНО: добавлен rate limiting (см. internal/ratelimit) — без него
// пароль можно было подбирать без ограничений.
func (h *Handler) login(c *gin.Context) {
	var req domain.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Неверные данные"})
		return
	}

	ip := c.ClientIP()
	userKey := "login:" + ip + ":" + strings.ToLower(req.Username)
	ipKey := "login_ip:" + ip

	if allowed, retryAfter := h.loginIPLimiter.Allowed(ipKey); !allowed {
		c.JSON(http.StatusTooManyRequests, gin.H{
			"error":               "too_many_attempts",
			"message":             "Слишком много попыток входа с этого устройства/сети. Попробуйте позже.",
			"retry_after_seconds": int(retryAfter.Seconds()),
		})
		return
	}
	if allowed, retryAfter := h.loginLimiter.Allowed(userKey); !allowed {
		c.JSON(http.StatusTooManyRequests, gin.H{
			"error":               "too_many_attempts",
			"message":             "Слишком много неудачных попыток входа. Попробуйте позже.",
			"retry_after_seconds": int(retryAfter.Seconds()),
		})
		return
	}

	user, err := h.userRepo.GetByUsername(context.Background(), req.Username)
	if err != nil || !auth.CheckPasswordHash(req.Password, user.PasswordHash) {
		h.loginLimiter.RecordFailure(userKey)
		h.loginIPLimiter.RecordFailure(ipKey)
		logWarn(c, "Неудачная попытка входа", "username", req.Username, "ip", ip)
		c.JSON(401, gin.H{"error": "Неверный логин или пароль"})
		return
	}
	h.loginLimiter.Reset(userKey)

	// Определяем, в контексте какого магазина будет работать токен владельца:
	// используем последний выбранный (current_shop_id), если он всё ещё
	// существует, иначе — первый магазин компании. Если магазинов ещё нет —
	// shopID = 0, и фронтенд обязан предложить создать первый магазин.
	shops, err := h.shopRepo.GetAllByCompany(context.Background(), user.CompanyID)
	if err != nil {
		logErr(c, err, "Ошибка получения списка магазинов при логине", "company_id", user.CompanyID)
		c.JSON(500, gin.H{"error": "Ошибка сервера"})
		return
	}

	shopID := 0
	shopName := ""
	needsShopSetup := len(shops) == 0
	if !needsShopSetup {
		shopID = shops[0].ID
		shopName = shops[0].Name
		for _, s := range shops {
			if s.ID == user.CurrentShopID {
				shopID = s.ID
				shopName = s.Name
				break
			}
		}
		if shopID != user.CurrentShopID {
			_ = h.userRepo.SetCurrentShop(context.Background(), user.ID, shopID)
		}
	}

	token, errToken := auth.GenerateToken(user.ID, user.CompanyID, shopID, user.Role, os.Getenv("JWT_SECRET"))
	if errToken != nil {
		logErr(c, errToken, "Ошибка генерации JWT токена при логине", "user_id", user.ID, "company_id", user.CompanyID)
		c.JSON(500, gin.H{"error": "Ошибка сервера при создании сессии"})
		return
	}

	// Получаем название компании для терминального режима
	companyName := ""
	if company, err := h.companyRepo.GetByID(context.Background(), user.CompanyID); err == nil {
		companyName = company.Name
	}

	c.JSON(200, gin.H{
		"token":            token,
		"role":             user.Role,
		"username":         user.Username,
		"company_id":       user.CompanyID,
		"company_name":     companyName,
		"shop_id":          shopID,
		"shop_name":        shopName,
		"needs_shop_setup": needsShopSetup,
	})
}
