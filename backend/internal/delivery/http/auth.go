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
func (h *Handler) login(c *gin.Context) {
	var req domain.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Неверные данные"})
		return
	}

	user, err := h.userRepo.GetByUsername(context.Background(), req.Username)
	if err != nil || !auth.CheckPasswordHash(req.Password, user.PasswordHash) {
		c.JSON(401, gin.H{"error": "Неверный логин или пароль"})
		return
	}
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
