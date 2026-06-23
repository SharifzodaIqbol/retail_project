package http

import (
	"context"
	"errors"
	"log"
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
			c.JSON(http.StatusConflict, gin.H{
				"error":  "trial_not_allowed",
				"reason": trialErr.Reason,
				// Не говорим "устройство найдено" — просто предлагаем купить
				"message": "Пробный период для этого устройства уже был использован. Свяжитесь с нами для подключения.",
			})
			return
		}
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
		c.JSON(401, gin.H{"error": "Неверный логин или пароль"})
		return
	}
	h.loginLimiter.Reset(userKey)

	token, errToken := auth.GenerateToken(user.ID, user.CompanyID, user.Role, os.Getenv("JWT_SECRET"))
	if errToken != nil {
		log.Println("Ошибка генерации JWT токена:", errToken)
		c.JSON(500, gin.H{"error": "Ошибка сервера при создании сессии"})
		return
	}

	// Получаем название компании для терминального режима
	companyName := ""
	if company, err := h.companyRepo.GetByID(context.Background(), user.CompanyID); err == nil {
		companyName = company.Name
	}

	c.JSON(200, gin.H{
		"token":        token,
		"role":         user.Role,
		"username":     user.Username,
		"company_id":   user.CompanyID,
		"company_name": companyName,
	})
}
