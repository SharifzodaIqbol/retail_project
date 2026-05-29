package main

import (
	"context"
	"log"
	"os"
	"time"

	"retail-managment-system/internal/delivery/http"
	"retail-managment-system/internal/delivery/telegram"
	"retail-managment-system/internal/repository"

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
	companyRepo := repository.NewCompanyRepository(dbPool)

	tgBot, err := telegram.NewBot(os.Getenv("TELEGRAM_APITOKEN"))
	if err != nil {
		log.Fatalf("Ошибка запуска бота: %v", err)
	}
	go tgBot.Start(saleRepo, userRepo, productRepo)

	// Ежедневный отчет в 21:00
	go startDailyReportScheduler(saleRepo, userRepo, tgBot)
	handler := http.NewHandler(productRepo, saleRepo, userRepo, companyRepo, tgBot, dbPool)
	router := handler.InitRoutes()
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("Сервер запущен на порту %s", port)
	router.Run(":" + port)
}
func startDailyReportScheduler(saleRepo *repository.SaleRepository, userRepo *repository.UserRepository, tgBot *telegram.Bot) {
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
}
