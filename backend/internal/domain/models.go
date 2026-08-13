package domain

import (
	"strings"
	"time"
)

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
	Barcode   *string `json:"barcode"`
	BuyPrice  float64 `json:"buy_price"`
	SellPrice float64 `json:"sell_price"`
	Stock     float64 `json:"stock"`
	Unit      string  `json:"unit"`
	IsActive  bool    `json:"is_active"`
	// Units — единицы продажи товара (шт/упаковка/блок...). Заполняется
	// отдельным запросом (см. ProductRepository.GetUnitsForProducts) там,
	// где это нужно клиенту: карточка товара, поиск по имени, штрихкод.
	// omitempty, чтобы не раздувать легковесные списки (GetAll), где
	// единицы не нужны.
	Units []ProductUnit `json:"units,omitempty"`
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

// ImportContext — состояние, подгружаемое ОДИН раз перед обработкой всего
// файла импорта (а не на каждую строку), чтобы избежать N+1 запросов к БД:
//
//   - Barcodes    — все штрихкоды компании (products + product_units),
//     используется для подбора свободного сгенерированного штрихкода
//     в памяти, без похода в БД на каждую попытку.
//   - NameToBarcode — имя товара (нормализовано: TrimSpace+ToLower) -> его
//     текущий штрихкод, в рамках конкретного магазина. Нужен, чтобы при
//     повторном импорте строки БЕЗ штрихкода находить уже существующий
//     товар по названию вместо генерации нового штрихкода (что раньше
//     приводило к дублированию товаров без штрихкода при повторной
//     загрузке одного и того же файла).
//   - ProductLabels — штрихкод товара -> набор названий уже существующих
//     у него доп. единиц продажи (упаковка/блок/...). Нужен для проверки
//     лимита MaxExtraUnitsPerProduct без SELECT на каждую строку.
type ImportContext struct {
	Barcodes      map[string]bool
	NameToBarcode map[string]string
	ProductLabels map[string]map[string]bool
}

// NormalizeImportName — единая нормализация имени товара для сопоставления
// строк импорта с уже существующими товарами (см. ImportContext.NameToBarcode).
func NormalizeImportName(name string) string {
	return strings.ToLower(strings.TrimSpace(name))
}

// SaleItem — позиция чека.
//
// На вход от кассира (executeSale) приходят ТОЛЬКО ProductID, UnitID и
// QuantityDisplay — то, что кассир реально выбрал ("1 упаковка"). Сервер
// сам подставляет ConversionFactor выбранной единицы продажи и считает
// QuantityBase = QuantityDisplay * ConversionFactor — именно это число
// списывается со склада и участвует в расчёте прибыли. Клиент никогда не
// присылает QuantityBase напрямую: пересчёт — обязанность бэкенда, а не
// фронтенда (иначе несогласованное округление на разных платформах могло
// бы тихо разъехаться со складом).
type SaleItem struct {
	SaleID    int `json:"sale_id"`
	ProductID int `json:"product_id"`
	UnitID    int `json:"unit_id" binding:"required"`
	// QuantityDisplay — что выбрал кассир в единицах продажи ("1 упаковка").
	// Для чека/UI. НИКОГДА не используется для списания склада напрямую.
	QuantityDisplay float64 `json:"quantity_display" binding:"required,gt=0"`
	// QuantityBase — учётное количество в базовых единицах (шт/кг).
	// Заполняется сервером при оформлении продажи, игнорируется если
	// прислано клиентом (см. SaleRepository.ExecuteSale).
	QuantityBase float64 `json:"quantity_base"`
	PriceAtSale  float64 `json:"price"`
	// BuyPriceAtSale — закупочная цена товара НА МОМЕНТ этой продажи.
	// Заполняется сервером внутри ExecuteSale (снимок текущей
	// products.buy_price в момент чека), клиент это поле не присылает и
	// не может повлиять на него. Без этого снимка вся историческая
	// прибыль пересчитывалась бы задним числом при каждом изменении
	// закупочной цены товара (правка карточки, переимпорт из Excel) —
	// именно так аналитика "расходилась с реальной прибылью".
	BuyPriceAtSale float64 `json:"-"`
}

type Sale struct {
	ID           int     `json:"id"`
	SellerID     int     `json:"seller_id"`
	SellerName   string  `json:"seller_name,omitempty"`
	ShopID       int     `json:"shop_id,omitempty"`
	TotalAmount  float64 `json:"total_amount"`
	IsCanceled   bool    `json:"is_canceled"`
	CancelReason *string `json:"cancel_reason"`
	CreatedAt    string  `json:"created_at,omitempty"`
}

type User struct {
	ID            int    `json:"id"`
	CompanyID     int    `json:"company_id"`
	Username      string `json:"username"`
	PasswordHash  string `json:"-"`
	PinHash       string `json:"-"`
	Role          string `json:"role"`
	TgChatID      int64  `json:"tg_chat_id"`
	HasPin        bool   `json:"has_pin"`                   // только для UI: есть ли PIN
	ShopID        int    `json:"shop_id,omitempty"`         // магазин продавца (фиксированный)
	ShopName      string `json:"shop_name,omitempty"`       // название магазина (для списка сотрудников)
	CurrentShopID int    `json:"current_shop_id,omitempty"` // текущий выбранный магазин владельца
}

type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

// PinLoginRequest — вход продавца через PIN в терминальном режиме.
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
type CreateUserRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password"`
	Role     string `json:"role" binding:"required"`
	Pin      string `json:"pin"`
	ShopID   int    `json:"shop_id"`
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

// RefreshRequest — обмен refresh-токена на новую пару токенов (см.
// POST /refresh). device_id опционален и нужен только для будущей
// возможности "выйти на этом устройстве"/показа списка сессий —
// сейчас используется только для записи в БД.
type RefreshRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

// LogoutRequest — инвалидация refresh-токена на сервере при явном выходе,
// чтобы токен нельзя было использовать повторно, даже если он не истёк.
type LogoutRequest struct {
	RefreshToken string `json:"refresh_token"`
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
	ShopID    int       `json:"shop_id,omitempty"`
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
	InitialDebt float64 `json:"initial_debt"`
	Note        string  `json:"note"`
}

// DebtOperationRequest — частичная оплата ("pay") или добавление долга ("take")
type DebtOperationRequest struct {
	Amount float64 `json:"amount" binding:"required,gt=0"`
	Type   string  `json:"type"   binding:"required,oneof=take pay"`
	Note   string  `json:"note"`
}

// ─── Пагинация ────────────────────────────────────────────────────────────────

// PaginatedResponse — универсальный ответ с пагинацией.
// Data содержит элементы текущей страницы ([]Product, []Sale, []Debtor и т.д.).
type PaginatedResponse struct {
	Data       interface{} `json:"data"`
	Total      int         `json:"total"`       // всего записей
	Page       int         `json:"page"`        // текущая страница (с 1)
	Limit      int         `json:"limit"`       // размер страницы
	TotalPages int         `json:"total_pages"` // всего страниц
}
