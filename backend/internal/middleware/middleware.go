package middleware

import (
	"context"
	"net/http"
	"retail-managment-system/internal/auth"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

func AuthMiddleware(secret string) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if len(authHeader) < 7 || authHeader[:7] != "Bearer " {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Нужна авторизация"})
			return
		}

		tokenString := authHeader[7:]
		claims := &auth.Claims{}

		token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
			return []byte(secret), nil
		})

		if err != nil || !token.Valid {
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
