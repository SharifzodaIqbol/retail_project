package http

import (
	"os"
	"retail-managment-system/internal/delivery/telegram"
	"retail-managment-system/internal/middleware"
	"retail-managment-system/internal/repository"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Handler struct {
	productRepo *repository.ProductRepository
	saleRepo    *repository.SaleRepository
	userRepo    *repository.UserRepository
	companyRepo *repository.CompanyRepository
	tgBot       *telegram.Bot
	dbPool      *pgxpool.Pool // нужен для кастомных SQL-запросов вроде отмены чека
}

func NewHandler(
	productRepo *repository.ProductRepository,
	saleRepo *repository.SaleRepository,
	userRepo *repository.UserRepository,
	companyRepo *repository.CompanyRepository,
	tgBot *telegram.Bot,
	dbPool *pgxpool.Pool,
) *Handler {
	return &Handler{
		productRepo: productRepo,
		saleRepo:    saleRepo,
		userRepo:    userRepo,
		companyRepo: companyRepo,
		tgBot:       tgBot,
		dbPool:      dbPool,
	}
}

// InitRoutes регистрирует все роуты
func (h *Handler) InitRoutes() *gin.Engine {
	r := gin.Default()
	r.Use(middleware.CorsMiddleware())

	// Публичные роуты
	r.POST("/register", h.register)
	r.POST("/login", h.login)

	// ─── Терминальный режим (публичные, без JWT) ───────────────────────────────
	// Получить список сотрудников для экрана выбора сотрудника
	r.GET("/terminal/users", h.getTerminalUsers)
	// Войти через PIN (возвращает JWT)
	r.POST("/terminal/pin-login", h.pinLogin)

	// Защищённые роуты
	api := r.Group("/api")
	api.Use(middleware.AuthMiddleware(os.Getenv("JWT_SECRET")))
	api.Use(middleware.SubscriptionMiddleware(h.dbPool))
	{
		// Товары
		api.GET("/products/search", h.searchProducts)
		api.GET("/products/:barcode", h.getProductByBarcode)
		api.GET("/products", h.getAllProducts)
		api.POST("/products", h.createProduct)
		api.PATCH("/products/:id/inventory", h.updateInventory)
		api.DELETE("/products/:id", h.deleteProduct)

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
			// Установить / изменить PIN сотруднику
			users.PUT("/:id/pin", h.setUserPin)
		}

		// Telegram привязка (только owner)
		tg := api.Group("/telegram")
		tg.Use(middleware.RoleMiddleware("owner"))
		{
			// Сгенерировать одноразовый токен → deeplink для привязки
			tg.POST("/link-token", h.generateTgLinkToken)
			// Отвязать Telegram
			tg.DELETE("/link", h.unlinkTelegram)
		}
	}

	return r
}
