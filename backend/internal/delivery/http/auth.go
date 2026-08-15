package http

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"retail-managment-system/internal/auth"
	"retail-managment-system/internal/domain"
	"retail-managment-system/internal/repository"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// Границы длины логина/пароля/названия компании — те же, что на клиенте
// (login_screen.dart / register_screen.dart), но здесь это настоящая
// защита, а не просто UX: клиентские проверки легко обойти прямым
// запросом к API.
const (
	minUsernameLength    = 3
	maxUsernameLength    = 50
	minPasswordLength    = 6
	maxPasswordLength    = 72 // bcrypt всё равно молча обрезает после 72 байт
	maxCompanyNameLength = 80
)

// validateCredentials проверяет длину логина и пароля после trim.
// Возвращает пустую строку, если всё в порядке, иначе — сообщение для
// клиента.
func validateCredentials(username, password string) string {
	switch {
	case len(username) < minUsernameLength:
		return fmt.Sprintf("Логин бояд ками-кам аз %d аломат иборат бошад", minUsernameLength)
	case len(username) > maxUsernameLength:
		return fmt.Sprintf("Логин набояд аз %d аломат зиёд бошад", maxUsernameLength)
	case len(password) < minPasswordLength:
		return fmt.Sprintf("Рамз бояд ками-кам аз %d аломат иборат бошад", minPasswordLength)
	case len(password) > maxPasswordLength:
		return fmt.Sprintf("Рамз набояд аз %d аломат зиёд бошад", maxPasswordLength)
	}
	return ""
}

func (h *Handler) register(c *gin.Context) {
	var req domain.RegisterCompanyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	req.Username = strings.TrimSpace(req.Username)
	req.CompanyName = strings.TrimSpace(req.CompanyName)

	if req.CompanyName == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Номи мағоза холӣ буда наметавонад"})
		return
	}
	if len(req.CompanyName) > maxCompanyNameLength {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": fmt.Sprintf("Номи мағоза набояд аз %d аломат зиёд бошад", maxCompanyNameLength),
		})
		return
	}
	if msg := validateCredentials(req.Username, req.Password); msg != "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
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

func (h *Handler) login(c *gin.Context) {
	var req domain.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Неверные данные"})
		return
	}

	req.Username = strings.TrimSpace(req.Username)

	// Простая проверка длины — до обращения к лимитеру и БД, чтобы не
	// тратить лимит попыток и запросы к БД на заведомо мусорный ввод
	// (пустая строка, гигантская вставка и т.п.).
	if len(req.Username) < minUsernameLength || len(req.Username) > maxUsernameLength ||
		len(req.Password) == 0 || len(req.Password) > maxPasswordLength {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Логин ё рамз нодуруст аст"})
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

	refreshToken, errRefresh := h.issueRefreshToken(c, user.ID)
	if errRefresh != nil {
		logErr(c, errRefresh, "Ошибка выдачи refresh-токена при логине", "user_id", user.ID)
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
		"refresh_token":    refreshToken,
		"role":             user.Role,
		"username":         user.Username,
		"company_id":       user.CompanyID,
		"company_name":     companyName,
		"shop_id":          shopID,
		"shop_name":        shopName,
		"needs_shop_setup": needsShopSetup,
	})
}

func (h *Handler) issueRefreshToken(c *gin.Context, userID int) (string, error) {
	raw, hash, err := auth.GenerateRefreshToken()
	if err != nil {
		return "", err
	}
	deviceID := c.GetHeader("X-Device-ID")
	expiresAt := time.Now().Add(auth.RefreshTokenTTL)
	if err := h.userRepo.CreateRefreshToken(context.Background(), userID, hash, deviceID, expiresAt); err != nil {
		return "", err
	}
	return raw, nil
}

func (h *Handler) refresh(c *gin.Context) {
	var req domain.RefreshRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Неверные данные"})
		return
	}

	hash := auth.HashRefreshToken(req.RefreshToken)
	user, err := h.userRepo.GetUserByValidRefreshToken(context.Background(), hash)
	if err != nil {
		logWarn(c, "Обновление токена: refresh-токен невалиден, истёк или отозван", "ip", c.ClientIP())
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Сессия истекла, нужно войти заново"})
		return
	}

	if err := h.userRepo.RevokeRefreshToken(context.Background(), hash); err != nil {
		logErr(c, err, "Обновление токена: не удалось отозвать старый refresh-токен", "user_id", user.ID)
	}

	shopID := user.ShopID
	if user.Role == "owner" {
		shopID = user.CurrentShopID
	}

	newAccessToken, errToken := auth.GenerateToken(user.ID, user.CompanyID, shopID, user.Role, os.Getenv("JWT_SECRET"))
	if errToken != nil {
		logErr(c, errToken, "Обновление токена: ошибка генерации нового JWT", "user_id", user.ID)
		c.JSON(500, gin.H{"error": "Ошибка сервера"})
		return
	}

	newRefreshToken, errRefresh := h.issueRefreshToken(c, user.ID)
	if errRefresh != nil {
		logErr(c, errRefresh, "Обновление токена: ошибка выдачи нового refresh-токена", "user_id", user.ID)
		c.JSON(500, gin.H{"error": "Ошибка сервера"})
		return
	}

	c.JSON(200, gin.H{
		"token":         newAccessToken,
		"refresh_token": newRefreshToken,
		"role":          user.Role,
		"shop_id":       shopID,
	})
}

func (h *Handler) logout(c *gin.Context) {
	var req domain.LogoutRequest
	_ = c.ShouldBindJSON(&req)
	if req.RefreshToken != "" {
		hash := auth.HashRefreshToken(req.RefreshToken)
		if err := h.userRepo.RevokeRefreshToken(context.Background(), hash); err != nil {
			logErr(c, err, "Ошибка отзыва refresh-токена при выходе")
		}
	}
	c.JSON(200, gin.H{"status": "ok"})
}
