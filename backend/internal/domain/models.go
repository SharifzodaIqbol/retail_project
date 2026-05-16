package domain

type Product struct {
	ID        int     `json:"id"`
	Name      string  `json:"name"`
	Barcode   string  `json:"barcode"`
	BuyPrice  float64 `json:"buy_price"`
	SellPrice float64 `json:"sell_price"`
	Stock     int     `json:"stock"`
	IsActive  bool    `json:"is_active"`
}

type SaleItem struct {
	SaleID      int     `json:"sale_id"`
	ProductID   int     `json:"product_id"`
	Quantity    int     `json:"quantity"`
	PriceAtSale float64 `json:"price"`
}

type Sale struct {
	ID           int     `json:"id"`
	SellerID     int     `json:"seller_id"`
	SellerName   string  `json:"seller_name,omitempty"`
	TotalAmount  float64 `json:"total_amount"`
	IsCanceled   bool    `json:"is_canceled"`
	CancelReason *string `json:"cancel_reason"`
	CreatedAt    string  `json:"created_at,omitempty"`
}

type User struct {
	ID           int    `json:"id"`
	Username     string `json:"username"`
	PasswordHash string `json:"-"`
	Role         string `json:"role"`
	TgChatID     int64  `json:"tg_chat_id"`
}

type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

type DailyStats struct {
	Total float64 `json:"total"`
	Count int     `json:"count"`
}

// НОВЫЕ типы для аналитики

type PeriodSummary struct {
	Revenue    float64 `json:"revenue"`
	Profit     float64 `json:"profit"`
	SalesCount int     `json:"sales_count"`
	AvgCheck   float64 `json:"avg_check"`
}

type TopProduct struct {
	ProductID  int     `json:"product_id"`
	Name       string  `json:"name"`
	TotalQty   int     `json:"total_qty"`
	TotalRev   float64 `json:"total_revenue"`
	TotalProfit float64 `json:"total_profit"`
}

type SaleByDay struct {
	Date    string  `json:"date"`
	Revenue float64 `json:"revenue"`
	Profit  float64 `json:"profit"`
	Count   int     `json:"count"`
}

type SellerStat struct {
	SellerID   int     `json:"seller_id"`
	Username   string  `json:"username"`
	SalesCount int     `json:"sales_count"`
	TotalRev   float64 `json:"total_revenue"`
}
