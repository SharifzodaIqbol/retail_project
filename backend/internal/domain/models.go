package domain

import "database/sql"

type Product struct {
	ID        int     `json:"id"`
	Name      string  `json:"name"`
	Barcode   string  `json:"barcode"`
	BuyPrice  float64 `json:"buy_price"`
	SellPrice float64 `json:"sell_price"`
	Stock     int     `json:"stock"`
}
type SaleItem struct {
	SaleID      int     `json:"sale_id"`
	ProductID   int     `json:"product_id"`
	Quantity    int     `json:"quantity"`
	PriceAtSale float64 `json:"price"`
}
type Sale struct {
	ID           int            `json:"id"`
	SellerID     int            `json:"seller_id"`
	TotalAmount  float64        `json:"total_amount"`
	IsCanceled   bool           `json:"is_canceled"`
	CancelReason sql.NullString `json:"cancel_reason"`
}
type User struct {
	ID           int    `json:"id"`
	Username     string `json:"username"`
	PasswordHash string `json:"-"` // Хеш пароля не должен улетать в JSON
	Role         string `json:"role"`
	TgChatID     int64  `json:"tg_chat_id"`
}

type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}
