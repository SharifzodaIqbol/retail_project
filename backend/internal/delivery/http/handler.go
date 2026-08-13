package http

import (
	"os"
	"retail-managment-system/internal/delivery/telegram"
	"retail-managment-system/internal/middleware"
	"retail-managment-system/internal/ratelimit"
	"retail-managment-system/internal/repository"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Handler struct {
	productRepo     *repository.ProductRepository
	productUnitRepo *repository.ProductUnitRepository
	saleRepo        *repository.SaleRepository
	userRepo        *repository.UserRepository
	companyRepo     *repository.CompanyRepository
	shopRepo        *repository.ShopRepository
	debtorRepo      *repository.DebtorRepository
	tgBot           *telegram.Bot
	dbPool          *pgxpool.Pool

	// Rate limiting на вход (см. internal/ratelimit) — защита от подбора
	// пароля владельца и особенно 4-значного PIN продавца.
	loginLimiter   *ratelimit.Limiter // по ключу IP+username
	loginIPLimiter *ratelimit.Limiter // по ключу IP (от распределённого перебора логинов)
	pinLimiter     *ratelimit.Limiter // по ключу IP+company_id+user_id
	pinIPLimiter   *ratelimit.Limiter // по ключу IP (от перебора чужих user_id с одного адреса)
}

func NewHandler(
	productRepo *repository.ProductRepository,
	productUnitRepo *repository.ProductUnitRepository,
	saleRepo *repository.SaleRepository,
	userRepo *repository.UserRepository,
	companyRepo *repository.CompanyRepository,
	shopRepo *repository.ShopRepository,
	debtorRepo *repository.DebtorRepository,
	tgBot *telegram.Bot,
	dbPool *pgxpool.Pool,
) *Handler {
	return &Handler{
		productRepo:     productRepo,
		productUnitRepo: productUnitRepo,
		saleRepo:        saleRepo,
		userRepo:        userRepo,
		companyRepo:     companyRepo,
		shopRepo:        shopRepo,
		debtorRepo:      debtorRepo,
		tgBot:           tgBot,
		dbPool:          dbPool,

		// 5 неудачных попыток за 15 минут -> блок на 15 минут для конкретной пары IP+username/PIN.
		loginLimiter: ratelimit.New(5, 15*time.Minute, 15*time.Minute),
		pinLimiter:   ratelimit.New(5, 15*time.Minute, 15*time.Minute),
		// Более мягкий, но всё же ограничивающий лимит по IP в целом —
		// чтобы нельзя было перебирать много разных username/user_id с одного адреса.
		loginIPLimiter: ratelimit.New(30, 15*time.Minute, 30*time.Minute),
		pinIPLimiter:   ratelimit.New(30, 15*time.Minute, 30*time.Minute),
	}
}

// InitRoutes регистрирует все роуты
func (h *Handler) InitRoutes() *gin.Engine {
	r := gin.New()
	r.Use(middleware.RequestID())
	r.Use(middleware.Recovery())
	r.Use(middleware.AccessLog())
	r.Use(middleware.CorsMiddleware())

	// Публичные роуты
	r.POST("/register", h.register)
	r.POST("/login", h.login)

	// Лёгкий health-check без авторизации и без обращения к БД —
	// используется мобильным клиентом (ConnectivityService) для проверки
	// РЕАЛЬНОЙ достижимости сервера, а не только наличия сетевого
	// интерфейса (Wi-Fi/моб. сеть может быть подключена, но без
	// доступа к интернету/серверу — например, локальный роутер без WAN).
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})

	// ─── Терминальный режим (публичные, без JWT) ───────────────────────────────
	r.GET("/terminal/users", h.getTerminalUsers)
	r.POST("/terminal/pin-login", h.pinLogin)

	// Защищённые роуты
	api := r.Group("/api")
	api.Use(middleware.AuthMiddleware(os.Getenv("JWT_SECRET")))
	api.Use(middleware.SubscriptionMiddleware(h.dbPool))
	{
		// Товары
		api.GET("/products/search", h.searchProducts)
		api.GET("/products/barcode/:barcode", h.getProductByBarcode)
		api.GET("/products/generate-barcode", h.generateBarcode)
		api.GET("/products", h.getAllProducts)
		api.POST("/products", h.createProduct)
		api.PUT("/products/:id", h.updateProduct)
		api.POST("/products/import", h.importProducts)
		api.PATCH("/products/:id/inventory", h.updateInventory)
		api.DELETE("/products/:id", h.deleteProduct)

		// Единицы продажи товара (шт/упаковка/блок...) — задача: продажа одного
		// товара в разных единицах.
		api.GET("/products/:id/units", h.getProductUnits)
		api.POST("/products/:id/units", h.createProductUnit)
		api.PUT("/products/:id/units/:unit_id", h.updateProductUnit)
		api.DELETE("/products/:id/units/:unit_id", h.deleteProductUnit)

		// Продажи
		sales := api.Group("/sales")
		{
			sales.POST("", h.executeSale)
			sales.GET("", h.getSalesHistory)
			sales.POST("/:id/cancel", h.cancelSale)
		}

		// Аналитика (только owner)
		analytics := api.Group("/analytics")
		analytics.Use(middleware.RoleMiddleware("owner"))
		{
			analytics.GET("/summary", h.getAnalyticsSummary)
			analytics.GET("/top-products", h.getTopProducts)
			analytics.GET("/sales-by-day", h.getSalesByDay)
			analytics.GET("/low-stock", h.getLowStock)
			analytics.GET("/sellers", h.getSellerStats)
		}

		// Пользователи (только owner)
		users := api.Group("/users")
		users.Use(middleware.RoleMiddleware("owner"))
		{
			users.GET("", h.getAllUsers)
			users.POST("", h.createUser)
			users.DELETE("/:id", h.deleteUser)
			users.PUT("/:id/pin", h.setUserPin)
		}

		// Магазины (только owner) — задача #2
		shops := api.Group("/shops")
		shops.Use(middleware.RoleMiddleware("owner"))
		{
			shops.GET("", h.getShops)
			shops.POST("", h.createShop)
			shops.PUT("/:id", h.updateShop)
			shops.DELETE("/:id", h.deleteShop)
			shops.POST("/:id/switch", h.switchShop)
		}

		// Telegram привязка (только owner)
		tg := api.Group("/telegram")
		tg.Use(middleware.RoleMiddleware("owner"))
		{
			tg.POST("/link-token", h.generateTgLinkToken)
			tg.DELETE("/link", h.unlinkTelegram)
		}

		// ─── Долговая книга (owner + seller) ──────────────────────────────────
		debtors := api.Group("/debtors")
		{
			debtors.GET("", h.getDebtors)                   // список должников
			debtors.POST("", h.createDebtor)                // добавить должника
			debtors.POST("/:id/operation", h.debtOperation) // оплата / новый долг
			debtors.GET("/:id/history", h.getDebtHistory)   // история операций

			// Удалить должника — только owner
			debtorsOwner := debtors.Group("")
			debtorsOwner.Use(middleware.RoleMiddleware("owner"))
			debtorsOwner.DELETE("/:id", h.deleteDebtor)
		}
	}

	return r
}
