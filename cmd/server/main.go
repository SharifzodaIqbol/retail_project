package main

import (
	"context"
	"log"
	"net/http"
	"os"

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
	// Загрузка переменных окружения
	if err := godotenv.Load(); err != nil {
		log.Print("No .env file found")
	}

	// Подключение к базе данных
	dbPool, err := pgxpool.New(context.Background(), os.Getenv("DATABASE_URL"))
	if err != nil {
		log.Fatalf("Ошибка пула БД %v\n", err)
	}
	defer dbPool.Close()

	if err := dbPool.Ping(context.Background()); err != nil {
		log.Fatalf("База недоступна: %v", err)
	}

	// Инициализация репозиториев
	productRepo := repository.NewProductRepository(dbPool)
	saleRepo := repository.NewSaleRepository(dbPool)
	userRepo := repository.NewUserRepository(dbPool)

	// Инициализация и запуск Telegram-бота
	tgBot, err := telegram.NewBot(os.Getenv("TELEGRAM_APITOKEN"))
	if err != nil {
		log.Printf("Ошибка инициализации бота: %v", err)
	} else {
		go tgBot.Start(saleRepo, userRepo)
	}

	jwtSecret := os.Getenv("JWT_SECRET")
	r := gin.Default()

	// --- ПУБЛИЧНЫЕ ЭНДПОИНТЫ ---

	// Регистрация нового пользователя
	r.POST("/register", func(c *gin.Context) {
		var req domain.LoginRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}

		hash, _ := auth.HashPassword(req.Password)
		user := domain.User{
			Username:     req.Username,
			PasswordHash: hash,
			Role:         "seller",
		}

		if err := userRepo.Create(context.Background(), user); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Пользователь уже существует"})
			return
		}
		c.JSON(http.StatusCreated, gin.H{"message": "Успешно"})
	})

	// Вход в систему и получение токена
	r.POST("/login", func(c *gin.Context) {
		var req domain.LoginRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}

		user, err := userRepo.GetByUsername(context.Background(), req.Username)
		if err != nil || !auth.CheckPasswordHash(req.Password, user.PasswordHash) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Неверный логин или пароль"})
			return
		}

		token, _ := auth.GenerateToken(user.ID, user.Role, jwtSecret)
		c.JSON(http.StatusOK, gin.H{"token": token})
	})

	api := r.Group("/api")
	api.Use(middleware.AuthMiddleware(jwtSecret)) // Проверка JWT-токена
	{
		// Поиск товара по штрихкоду
		api.GET("/products/:barcode", func(c *gin.Context) {
			barcode := c.Param("barcode")
			product, err := productRepo.GetByBarcode(context.Background(), barcode)
			if err != nil {
				c.JSON(http.StatusNotFound, gin.H{"error": "Товар не найден"})
				return
			}
			c.JSON(http.StatusOK, product)
		})

		// Добавление нового товара в базу
		api.POST("/products", func(c *gin.Context) {
			var newProduct domain.Product
			if err := c.ShouldBindJSON(&newProduct); err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
				return
			}
			productRepo.Create(context.Background(), newProduct)
			c.JSON(http.StatusCreated, gin.H{"message": "ОК"})
		})

		api.POST("/sales", func(c *gin.Context) {
			var input struct {
				Items []domain.SaleItem `json:"items"`
				Total float64           `json:"total"`
			}
			if err := c.ShouldBindJSON(&input); err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
				return
			}

			sellerID := c.MustGet("user_id").(int)

			saleID, err := saleRepo.ExecuteSale(context.Background(), sellerID, input.Items, input.Total)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}

			if tgBot != nil {
				ownerChatID, err := userRepo.GetOwnerChatID(context.Background())
				if err == nil && ownerChatID != 0 {
					go tgBot.SendSaleNotification(ownerChatID, saleID, input.Total)
				} else {
					log.Println("Хозяин не привязал Telegram, уведомление не отправлено")
				}
			}

			c.JSON(http.StatusOK, gin.H{
				"message": "Продажа оформлена",
				"sale_id": saleID,
			})
		})
	}
	r.Run()
}
