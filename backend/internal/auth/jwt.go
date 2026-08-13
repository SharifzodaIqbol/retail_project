package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const AccessTokenTTL = 24 * time.Hour

const RefreshTokenTTL = 30 * 24 * time.Hour

// Claims — это данные, которые мы "зашиваем" в токен
type Claims struct {
	UserID    int    `json:"user_id"`
	CompanyID int    `json:"company_id"`
	ShopID    int    `json:"shop_id"`
	Role      string `json:"role"`
	jwt.RegisteredClaims
}

func GenerateToken(userID, companyID, shopID int, role, secret string) (string, error) {
	claims := &Claims{
		UserID:    userID,
		CompanyID: companyID,
		ShopID:    shopID,
		Role:      role,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(AccessTokenTTL)),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(secret))
}

func GenerateRefreshToken() (raw string, hash string, err error) {
	b := make([]byte, 32)
	if _, err = rand.Read(b); err != nil {
		return "", "", err
	}
	raw = hex.EncodeToString(b)
	return raw, HashRefreshToken(raw), nil
}

func HashRefreshToken(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}
