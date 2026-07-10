package auth

import (
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Claims — это данные, которые мы "зашиваем" в токен
type Claims struct {
	UserID    int    `json:"user_id"`
	CompanyID int    `json:"company_id"`
	ShopID    int    `json:"shop_id"`
	Role      string `json:"role"`
	jwt.RegisteredClaims
}

// GenerateToken создает новый JWT токен на 24 часа.
// shopID — магазин, в контексте которого будет работать этот токен (0, если
// у владельца ещё нет ни одного магазина — тогда доступ к данным магазина
// не выдаётся, пока он не создаст первый).
func GenerateToken(userID, companyID, shopID int, role, secret string) (string, error) {
	claims := &Claims{
		UserID:    userID,
		CompanyID: companyID,
		ShopID:    shopID,
		Role:      role,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(24 * time.Hour)),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(secret))
}
