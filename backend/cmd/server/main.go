package main

import (
	"context"
	"log"
	"os"
	"strconv"
	"time"

	"retail-managment-system/internal/auth"
	"retail-managment-system/internal/delivery/telegram"
	"retail-managment-system/internal/domain"
	"retail-managment-system/internal/middleware"
	"retail-managment-system/internal/repository"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
)

func main() {
	if err := godotenv.Load(); err != nil {
		log.Print("Файл .env не найден, используем переменные окружения")
	}

	dbPool, err := pgxpool.New(context.Background(), os.Getenv("DATABASE_URL"))
	if err != nil {
		log.Fatalf("Ошибка подключения к БД: %v\n", err)
	}
	defer dbPool.Close()

	productRepo := repository.NewProductRepository(dbPool)
	saleRepo := repository.NewSaleRepository(dbPool)
	userRepo := repository.NewUserRepository(dbPool)

	tgBot, err := telegram.NewBot(os.Getenv("TELEGRAM_APITOKEN"))
	if err != nil {
		log.Fatalf("Ошибка запуска бота: %v", err)
	}
	go tgBot.Start(saleRepo, userRepo, productRepo)

	// Ежедневный отчет в 21:00
	go func() {
		log.Println("Планировщик отчетов запущен...")
		for {
			now := time.Now()
			if now.Hour() == 21 && now.Minute() == 0 {
				stats, err := saleRepo.GetTodayTotal(context.Background())
				if err == nil {
					ownerID, err := userRepo.GetOwnerChatID(context.Background())
					if err == nil && ownerID != 0 {
						tgBot.SendDailyReport(ownerID, stats.Total, stats.Count)
					}
				}
				time.Sleep(61 * time.Second)
			}
			time.Sleep(30 * time.Second)
		}
	}()

	r := gin.Default()
	r.Use(middleware.CorsMiddleware())

	// ─── Авторизация ───────────────────────────────────────────────────────────
	r.POST("/login", func(c *gin.Context) {
		var req domain.LoginRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(400, gin.H{"error": "Неверные данные"})
			return
		}
		user, err := userRepo.GetByUsername(context.Background(), req.Username)
		if err != nil || !auth.CheckPasswordHash(req.Password, user.PasswordHash) {
			c.JSON(401, gin.H{"error": "Неверный логин или пароль"})
			return
		}
		token, _ := auth.GenerateToken(user.ID, user.Role, os.Getenv("JWT_SECRET"))
		c.JSON(200, gin.H{"token": token, "role": user.Role, "username": user.Username})
	})

	// ─── Защищённые роуты ──────────────────────────────────────────────────────
	api := r.Group("/api")
	api.Use(middleware.AuthMiddleware(os.Getenv("JWT_SECRET")))
	{
		// ── Товары ──
		api.GET("/products/:barcode", func(c *gin.Context) {
			barcode := c.Param("barcode")
			p, err := productRepo.GetByBarcode(context.Background(), barcode)
			if err != nil {
				c.JSON(404, gin.H{"error": "Товар не найден"})
				return
			}
			c.JSON(200, p)
		})

		api.GET("/products/search", func(c *gin.Context) {
			name := c.Query("name")
			products, _ := productRepo.SearchByName(context.Background(), name)
			c.JSON(200, products)
		})

		api.GET("/products", func(c *gin.Context) {
			products, err := productRepo.GetAll(context.Background())
			if err != nil {
				c.JSON(500, gin.H{"error": "Ошибка получения товаров"})
				return
			}
			c.JSON(200, products)
		})

		api.POST("/products", func(c *gin.Context) {
			var p domain.Product
			if err := c.ShouldBindJSON(&p); err != nil {
				c.JSON(400, gin.H{"error": err.Error()})
				return
			}
			if err := productRepo.Create(context.Background(), p); err != nil {
				c.JSON(500, gin.H{"error": "Ошибка создания товара"})
				return
			}
			c.JSON(200, gin.H{"status": "ok"})
		})

		api.PATCH("/products/:id/inventory", func(c *gin.Context) {
			id, _ := strconv.Atoi(c.Param("id"))
			var input struct {
				Amount    int     `json:"amount"`
				SellPrice float64 `json:"sell_price"`
				BuyPrice  float64 `json:"buy_price"`
			}
			if err := c.ShouldBindJSON(&input); err != nil {
				c.JSON(400, gin.H{"error": "Неверный формат данных"})
				return
			}
			if err := productRepo.UpdateInventory(context.Background(), id, input.Amount, input.SellPrice, input.BuyPrice); err != nil {
				c.JSON(500, gin.H{"error": "Не удалось обновить склад"})
				return
			}
			c.JSON(200, gin.H{"status": "ok"})
		})

		// НОВОЕ: Удалить товар (soft delete)
		api.DELETE("/products/:id", func(c *gin.Context) {
			role := c.MustGet("role").(string)
			if role != "owner" {
				c.JSON(403, gin.H{"error": "Нет прав"})
				return
			}
			id, _ := strconv.Atoi(c.Param("id"))
			if err := productRepo.SoftDelete(context.Background(), id); err != nil {
				c.JSON(500, gin.H{"error": "Ошибка удаления"})
				return
			}
			c.JSON(200, gin.H{"status": "ok"})
		})

		// ── Продажи ──
		sales := api.Group("/sales")
		{
			sales.POST("", func(c *gin.Context) {
				var input struct {
					Items []domain.SaleItem `json:"items"`
					Total float64           `json:"total_amount"`
				}
				if err := c.ShouldBindJSON(&input); err != nil {
					c.JSON(400, gin.H{"error": err.Error()})
					return
				}
				sellerID := c.MustGet("user_id").(int)
				saleID, lowStockItems, err := saleRepo.ExecuteSale(context.Background(), sellerID, input.Items, input.Total)
				if err != nil {
					c.JSON(500, gin.H{"error": err.Error()})
					return
				}

				go func() {
					ownerID, _ := userRepo.GetOwnerChatID(context.Background())
					if ownerID != 0 {
						for _, item := range lowStockItems {
							tgBot.SendLowStockAlert(ownerID, item.Name, item.Stock)
						}
					}
				}()

				c.JSON(200, gin.H{"id": saleID})
			})

			sales.GET("", func(c *gin.Context) {
				history, _ := saleRepo.GetAll(context.Background())
				c.JSON(200, history)
			})

			sales.POST("/cancel", func(c *gin.Context) {
				var input struct {
					SaleID int    `json:"sale_id"`
					Reason string `json:"reason"`
				}
				if err := c.ShouldBindJSON(&input); err != nil {
					c.JSON(400, gin.H{"error": "Неверный формат данных"})
					return
				}

				var totalAmount float64
				err := dbPool.QueryRow(context.Background(), "SELECT total_amount FROM sales WHERE id = $1", input.SaleID).Scan(&totalAmount)
				if err != nil {
					c.JSON(404, gin.H{"error": "Чек не найден"})
					return
				}

				if err = saleRepo.CancelSale(context.Background(), input.SaleID, input.Reason); err != nil {
					c.JSON(500, gin.H{"error": "Не удалось отменить чек: " + err.Error()})
					return
				}

				go func() {
					ownerID, _ := userRepo.GetOwnerChatID(context.Background())
					if ownerID != 0 {
						tgBot.SendCancelNotification(ownerID, input.SaleID, input.Reason, totalAmount)
					}
				}()

				c.JSON(200, gin.H{"status": "ok"})
			})
		}

		// ── Аналитика (только owner) ──
		analytics := api.Group("/analytics")
		analytics.Use(middleware.RoleMiddleware("owner"))
		{
			// Выручка и прибыль за период
			analytics.GET("/summary", func(c *gin.Context) {
				period := c.DefaultQuery("period", "today")
				summary, err := saleRepo.GetPeriodSummary(context.Background(), period)
				if err != nil {
					c.JSON(500, gin.H{"error": "Ошибка получения данных"})
					return
				}
				c.JSON(200, summary)
			})

			// Топ продаж по товарам
			analytics.GET("/top-products", func(c *gin.Context) {
				limitStr := c.DefaultQuery("limit", "10")
				limit, _ := strconv.Atoi(limitStr)
				products, err := saleRepo.GetTopProductsDetailed(context.Background(), limit)
				if err != nil {
					c.JSON(500, gin.H{"error": "Ошибка"})
					return
				}
				c.JSON(200, products)
			})

			// Продажи по дням (для графика)
			analytics.GET("/sales-by-day", func(c *gin.Context) {
				days, _ := strconv.Atoi(c.DefaultQuery("days", "7"))
				data, err := saleRepo.GetSalesByDay(context.Background(), days)
				if err != nil {
					c.JSON(500, gin.H{"error": "Ошибка"})
					return
				}
				c.JSON(200, data)
			})

			// Товары с низким остатком
			analytics.GET("/low-stock", func(c *gin.Context) {
				threshold, _ := strconv.Atoi(c.DefaultQuery("threshold", "10"))
				products, err := productRepo.GetLowStockProducts(context.Background(), threshold)
				if err != nil {
					c.JSON(500, gin.H{"error": "Ошибка"})
					return
				}
				c.JSON(200, products)
			})

			// Статистика по продавцам
			analytics.GET("/sellers", func(c *gin.Context) {
				stats, err := saleRepo.GetSellerStats(context.Background())
				if err != nil {
					c.JSON(500, gin.H{"error": "Ошибка"})
					return
				}
				c.JSON(200, stats)
			})
		}

		// ── Пользователи (только owner) ──
		users := api.Group("/users")
		users.Use(middleware.RoleMiddleware("owner"))
		{
			users.GET("", func(c *gin.Context) {
				list, err := userRepo.GetAll(context.Background())
				if err != nil {
					c.JSON(500, gin.H{"error": "Ошибка"})
					return
				}
				c.JSON(200, list)
			})

			users.POST("", func(c *gin.Context) {
				var req struct {
					Username string `json:"username" binding:"required"`
					Password string `json:"password" binding:"required"`
					Role     string `json:"role" binding:"required"`
				}
				if err := c.ShouldBindJSON(&req); err != nil {
					c.JSON(400, gin.H{"error": err.Error()})
					return
				}
				hash, _ := auth.HashPassword(req.Password)
				user := domain.User{Username: req.Username, PasswordHash: hash, Role: req.Role}
				if err := userRepo.Create(context.Background(), user); err != nil {
					c.JSON(500, gin.H{"error": "Ошибка создания пользователя"})
					return
				}
				c.JSON(200, gin.H{"status": "ok"})
			})

			users.DELETE("/:id", func(c *gin.Context) {
				id, _ := strconv.Atoi(c.Param("id"))
				if err := userRepo.Delete(context.Background(), id); err != nil {
					c.JSON(500, gin.H{"error": "Ошибка удаления"})
					return
				}
				c.JSON(200, gin.H{"status": "ok"})
			})
		}
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("Сервер запущен на порту %s", port)
	r.Run(":" + port)
}
