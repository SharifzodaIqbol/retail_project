package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"retail-managment-system/internal/auth"
	"retail-managment-system/internal/domain"
	"retail-managment-system/internal/middleware"
	"retail-managment-system/internal/repository"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
)

func main() {
	if err := godotenv.Load(); err != nil {
		log.Print("No .env file found")
	}

	dbPool, err := pgxpool.New(context.Background(), os.Getenv("DATABASE_URL"))

	if err != nil {
		log.Fatalf("Ошибка пула БД %v\n", err)
		os.Exit(1)
	}
	defer dbPool.Close()

	if err := dbPool.Ping(context.Background()); err != nil {
		log.Fatalf("База недоступна: %v", err)
	}

	productRepo := repository.NewProductRepository(dbPool)
	saleRepo := repository.NewSaleRepository(dbPool)
	userRepo := repository.NewUserRepository(dbPool)

	jwtSecret := os.Getenv("JWT_SECRET")

	r := gin.Default()
	r.POST("/register", func(c *gin.Context) {
		var req domain.LoginRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}

		hash, _ := auth.HashPassword(req.Password)
		user := domain.User{Username: req.Username, PasswordHash: hash, Role: "seller"}

		if err := userRepo.Create(context.Background(), user); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Пользователь уже существует"})
			return
		}
		c.JSON(http.StatusCreated, gin.H{"message": "Успешно"})
	})

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
		//cannot use user (variable of struct type domain.User) as domain.Product value in argument to userRepo.Create
		token, _ := auth.GenerateToken(user.ID, user.Role, jwtSecret)
		c.JSON(http.StatusOK, gin.H{"token": token})
	})

	api := r.Group("/api")
	api.Use(middleware.AuthMiddleware(jwtSecret))
	{
		// Поиск товара (для сканера)
		api.GET("/products/:barcode", func(c *gin.Context) {
			barcode := c.Param("barcode")
			product, err := productRepo.GetByBarcode(context.Background(), barcode)
			if err != nil {
				c.JSON(http.StatusNotFound, gin.H{"error": "Товар не найден"})
				return
			}
			c.JSON(http.StatusOK, product)
		})

		// Добавление товара
		api.POST("/products", func(c *gin.Context) {
			var newProduct domain.Product
			if err := c.ShouldBindJSON(&newProduct); err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
				return
			}
			productRepo.Create(context.Background(), newProduct)
			c.JSON(http.StatusCreated, gin.H{"message": "ОК"})
		})

		// Оформление продажи
		api.POST("/sales", func(c *gin.Context) {
			var input struct {
				Items []domain.SaleItem `json:"items"`
				Total float64           `json:"total"`
			}
			if err := c.ShouldBindJSON(&input); err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
				return
			}

			// Берем ID продавца прямо из токена!
			sellerID := c.MustGet("user_id").(int)

			err := saleRepo.ExecuteSale(context.Background(), sellerID, input.Items, input.Total)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
			c.JSON(http.StatusOK, gin.H{"message": "Продажа оформлена"})
		})
	}
	r.Run()
}
