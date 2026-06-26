package domain

import "time"

type Company struct {
	ID          int       `json:"id"`
	Name        string    `json:"name"`
	BillingPlan string    `json:"billing_plan"`
	TrialEndsAt time.Time `json:"trial_ends_at"`
	IsPaid      bool      `json:"is_paid"`
	CreatedAt   time.Time `json:"created_at"`
}

// Shop — один магазин внутри компании (задача #2)
type Shop struct {
	ID        int    `json:"id"`
	CompanyID int    `json:"company_id"`
	Name      string `json:"name"`
}

type RegisterCompanyRequest struct {
	CompanyName string `json:"company_name" binding:"required"`
	Username    string `json:"username" binding:"required"`
	Password    string `json:"password" binding:"required"`
	DeviceID    string `json:"device_id"`
	Phone       string `json:"phone"`
}
type TrialDeniedReason string

const (
	TrialDeniedDevice TrialDeniedReason = "device_already_used"
	TrialDeniedPhone  TrialDeniedReason = "phone_already_used"
)

type TrialCheckResult struct {
	Allowed bool
	Reason  TrialDeniedReason
}

// Unit — единица измерения товара.
const (
	UnitPcs = "pcs" // штуки
	UnitKg  = "kg"  // килограммы (поддерживает дробный остаток)
)

type Product struct {
	ID        int     `json:"id"`
	CompanyID int     `json:"company_id"`
	ShopID    int     `json:"shop_id,omitempty"`
	Name      string  `json:"name"`
	Barcode   string  `json:"barcode"`
	BuyPrice  float64 `json:"buy_price"`
	SellPrice float64 `json:"sell_price"`
	// Stock — float64, так как товары с unit = "kg" могут иметь дробный остаток (например, 2.5 кг).
	Stock    float64 `json:"stock"`
	Unit     string  `json:"unit"`
	IsActive bool    `json:"is_active"`
}

// ProductImportResult — отчёт об импорте товаров из Excel.
type ProductImportResult struct {
	Created int                  `json:"created"`
	Updated int                  `json:"updated"`
	Errors  []ProductImportError `json:"errors"`
}

type ProductImportError struct {
	Row     int    `json:"row"`
	Message string `json:"message"`
}

type SaleItem struct {
	SaleID      int     `json:"sale_id"`
	ProductID   int     `json:"product_id"`
	Quantity    float64 `json:"quantity"`
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
	CompanyID    int    `json:"company_id"`
	Username     string `json:"username"`
	PasswordHash string `json:"-"`
	PinHash      string `json:"-"`
	Role         string `json:"role"`
	TgChatID     int64  `json:"tg_chat_id"`
	HasPin       bool   `json:"has_pin"` // только для UI: есть ли PIN
}

type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

// PinLoginRequest — вход продавца через PIN в терминальном режиме.
// CompanyID обязателен: раньше вход проверялся только по глобальному
// user_id + PIN, без привязки к компании. Поскольку PIN всего 4 цифры,
// это давало возможность подбора (10000 вариантов) против ЛЮБОГО
// пользователя в системе, а не только своей компании.
type PinLoginRequest struct {
	UserID    int    `json:"user_id" binding:"required"`
	CompanyID int    `json:"company_id" binding:"required"`
	Pin       string `json:"pin" binding:"required"`
}

// SetPinRequest — установка PIN для сотрудника
type SetPinRequest struct {
	Pin string `json:"pin" binding:"required"`
}

// CreateUserRequest — создание сотрудника.
// Для seller'ов пароль не нужен — они входят только через PIN.
type CreateUserRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password"` // обязателен только для owner, для seller — пустой
	Role     string `json:"role" binding:"required"`
	Pin      string `json:"pin"` // необязательный для seller, 4 цифры
}

// CreateShopRequest — создать новый магазин внутри компании
type CreateShopRequest struct {
	Name string `json:"name" binding:"required"`
}

// TgLinkTokenResponse — ответ с токеном для привязки Telegram
type TgLinkTokenResponse struct {
	Token   string `json:"token"`
	BotName string `json:"bot_name"`
}

type DailyStats struct {
	Total float64 `json:"total"`
	Count int     `json:"count"`
}

type PeriodSummary struct {
	Revenue    float64 `json:"revenue"`
	Profit     float64 `json:"profit"`
	SalesCount int     `json:"sales_count"`
	AvgCheck   float64 `json:"avg_check"`
}

type TopProduct struct {
	ProductID   int     `json:"product_id"`
	Name        string  `json:"name"`
	TotalQty    int     `json:"total_qty"`
	TotalRev    float64 `json:"total_revenue"`
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

// ─── Долговая книга ───────────────────────────────────────────────────────────

// Debtor — запись о должнике
type Debtor struct {
	ID        int       `json:"id"`
	CompanyID int       `json:"company_id"`
	FullName  string    `json:"full_name"`
	Phone     string    `json:"phone"`
	TotalDebt float64   `json:"total_debt"`
	UpdatedAt time.Time `json:"updated_at"`
}

// DebtHistory — одна операция по должнику: взял или вернул
type DebtHistory struct {
	ID        int       `json:"id"`
	DebtorID  int       `json:"debtor_id"`
	Amount    float64   `json:"amount"`
	Type      string    `json:"type"` // "take" | "pay"
	Note      string    `json:"note"`
	CreatedAt time.Time `json:"created_at"`
}

// CreateDebtorRequest — создать нового должника
type CreateDebtorRequest struct {
	FullName    string  `json:"full_name" binding:"required"`
	Phone       string  `json:"phone"`
	InitialDebt float64 `json:"initial_debt"` // начальная сумма долга (>0)
	Note        string  `json:"note"`
}

// DebtOperationRequest — частичная оплата ("pay") или добавление долга ("take")
type DebtOperationRequest struct {
	Amount float64 `json:"amount" binding:"required,gt=0"`
	Type   string  `json:"type"   binding:"required,oneof=take pay"`
	Note   string  `json:"note"`
}
