package middleware

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net/http"
	"retail-managment-system/internal/auth"
	"retail-managment-system/internal/logger"
	"runtime/debug"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// newRequestID генерирует короткий случайный идентификатор запроса.
// Используется (а не uuid), чтобы не тащить лишнюю зависимость.
func newRequestID() string {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		// Крайне маловероятно, но на случай ошибки crypto/rand не должно
		// падать — используем менее уникальный, но валидный fallback.
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(b)
}

// RequestID присваивает каждому запросу уникальный ID: если он уже пришёл
// в заголовке X-Request-ID (например, от прокси/балансировщика) — используем
// его, иначе генерируем новый. ID кладётся в gin.Context, в заголовок ответа
// и в логгер в контексте — это позволяет по одному ID найти все логи,
// относящиеся к конкретному HTTP-запросу.
func RequestID() gin.HandlerFunc {
	return func(c *gin.Context) {
		rid := c.GetHeader("X-Request-ID")
		if rid == "" {
			rid = newRequestID()
		}
		c.Set("request_id", rid)
		c.Writer.Header().Set("X-Request-ID", rid)

		l := logger.FromContext(c.Request.Context()).With("request_id", rid)
		c.Request = c.Request.WithContext(logger.WithContext(c.Request.Context(), l))
		c.Next()
	}
}

// AccessLog пишет один структурированный лог на каждый завершённый запрос:
// метод, путь, статус, длительность, IP и (если уже есть после AuthMiddleware)
// company_id/user_id/role. Уровень зависит от статус-кода: 5xx -> error,
// 4xx -> warn, остальное -> info. Это заменяет стандартный gin.Logger().
func AccessLog() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		c.Next()
		latency := time.Since(start)
		status := c.Writer.Status()

		l := logger.FromContext(c.Request.Context()).With(
			"method", c.Request.Method,
			"path", c.FullPath(),
			"query", c.Request.URL.RawQuery,
			"status", status,
			"latency_ms", latency.Milliseconds(),
			"ip", c.ClientIP(),
		)
		if companyID, ok := c.Get("company_id"); ok {
			l = l.With("company_id", companyID)
		}
		if userID, ok := c.Get("user_id"); ok {
			l = l.With("user_id", userID)
		}
		if role, ok := c.Get("role"); ok {
			l = l.With("role", role)
		}
		if len(c.Errors) > 0 {
			l = l.With("gin_errors", c.Errors.String())
		}

		switch {
		case status >= 500:
			l.Error("Запрос завершился с ошибкой сервера")
		case status >= 400:
			l.Warn("Запрос завершился с ошибкой клиента")
		default:
			l.Info("Запрос обработан")
		}
	}
}

// Recovery перехватывает панику в хендлерах, логирует её со стектрейсом
// (без этого паника просто уронит процесс или, в лучшем случае, потеряется
// в стандартном gin-recovery без структурированного лога) и отвечает 500,
// не давая процессу упасть.
func Recovery() gin.HandlerFunc {
	return func(c *gin.Context) {
		defer func() {
			if rec := recover(); rec != nil {
				logger.FromContext(c.Request.Context()).Error("Восстановление после паники в хендлере",
					"request_id", c.GetString("request_id"),
					"method", c.Request.Method,
					"path", c.FullPath(),
					"panic", fmt.Sprintf("%v", rec),
					"stack", string(debug.Stack()),
				)
				c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"error": "Внутренняя ошибка сервера"})
			}
		}()
		c.Next()
	}
}

// errString безопасно превращает error в строку для логов: err может быть
// nil даже в "ошибочной" ветке (например, когда токен распарсился, но
// token.Valid == false).
func errString(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

func AuthMiddleware(secret string) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if len(authHeader) < 7 || authHeader[:7] != "Bearer " {
			logger.FromContext(c.Request.Context()).Warn("Запрос без заголовка авторизации",
				"path", c.FullPath(), "ip", c.ClientIP())
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Нужна авторизация"})
			return
		}

		tokenString := authHeader[7:]
		claims := &auth.Claims{}

		token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
			return []byte(secret), nil
		})

		if err != nil || !token.Valid {
			logger.FromContext(c.Request.Context()).Warn("Невалидный или просроченный JWT токен",
				"path", c.FullPath(), "ip", c.ClientIP(), "error", errString(err))
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Неверный токен"})
			return
		}

		c.Set("user_id", claims.UserID)
		c.Set("company_id", claims.CompanyID)
		c.Set("role", claims.Role)
		c.Next()
	}
}

// RoleMiddleware — проверяет роль пользователя
func RoleMiddleware(requiredRole string) gin.HandlerFunc {
	return func(c *gin.Context) {
		role, exists := c.Get("role")
		if !exists || role.(string) != requiredRole {
			logger.FromContext(c.Request.Context()).Warn("Доступ запрещён: недостаточно прав",
				"path", c.FullPath(), "required_role", requiredRole, "role", role,
				"user_id", c.GetInt("user_id"), "company_id", c.GetInt("company_id"))
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "Нет прав доступа"})
			return
		}
		c.Next()
	}
}

// SubscriptionMiddleware блокирует доступ (HTTP 402), если триал истек и тариф не оплачен
func SubscriptionMiddleware(db *pgxpool.Pool) gin.HandlerFunc {
	return func(c *gin.Context) {
		companyID, exists := c.Get("company_id")
		if !exists {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Компания не идентифицирована"})
			return
		}

		var trialEndsAt time.Time
		var isPaid bool

		query := `SELECT trial_ends_at, is_paid FROM companies WHERE id = $1`
		err := db.QueryRow(context.Background(), query, companyID).Scan(&trialEndsAt, &isPaid)
		if err != nil {
			logger.FromContext(c.Request.Context()).Error("Не удалось проверить статус подписки компании",
				"company_id", companyID, "error", err.Error())
			c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"error": "Ошибка проверки подписки"})
			return
		}

		// Если доступ не оплачен и текущее время позже окончания триала
		if !isPaid && time.Now().After(trialEndsAt) {
			c.AbortWithStatusJSON(http.StatusPaymentRequired, gin.H{
				"error":   "subscription_expired",
				"message": "Срок действия подписки или пробного периода истек. Пожалуйста, оплатите тариф.",
			})
			return
		}

		c.Next()
	}
}
func CorsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE, PATCH")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	}
}
