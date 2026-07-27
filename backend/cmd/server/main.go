package main

import (
	"context"
	"log"
	"log/slog"
	"os"
	"time"

	"retail-managment-system/internal/delivery/http"
	"retail-managment-system/internal/delivery/telegram"
	"retail-managment-system/internal/logger"
	"retail-managment-system/internal/repository"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
)

func main() {
	l := logger.Init()

	if err := godotenv.Load(); err != nil {
		l.Info("Файл .env не найден, используем переменные окружения")
	}

	dbPool, err := pgxpool.New(context.Background(), os.Getenv("DATABASE_URL"))
	if err != nil {
		l.Error("Ошибка подключения к БД", "error", err.Error())
		os.Exit(1)
	}
	defer dbPool.Close()

	productRepo := repository.NewProductRepository(dbPool)
	saleRepo := repository.NewSaleRepository(dbPool)
	userRepo := repository.NewUserRepository(dbPool)
	companyRepo := repository.NewCompanyRepository(dbPool)
	shopRepo := repository.NewShopRepository(dbPool)
	debtorRepo := repository.NewDebtorRepository(dbPool)
	productUnitRepo := repository.NewProductUnitRepository(dbPool)
	tgBot, err := telegram.NewBot(os.Getenv("TELEGRAM_APITOKEN"))
	if err != nil {
		l.Error("Ошибка запуска Telegram-бота", "error", err.Error())
		os.Exit(1)
	}
	go tgBot.Start(saleRepo, userRepo, productRepo, debtorRepo)

	go startDailyReportScheduler(saleRepo, userRepo, tgBot, l)

	handler := http.NewHandler(productRepo, productUnitRepo, saleRepo, userRepo, companyRepo, shopRepo, debtorRepo, tgBot, dbPool)
	router := handler.InitRoutes()
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	l.Info("Сервер запущен", "port", port)
	if err := router.Run(":" + port); err != nil {
		log.Fatalf("Сервер остановлен из-за ошибки: %v", err)
	}
}
func startDailyReportScheduler(saleRepo *repository.SaleRepository, userRepo *repository.UserRepository, tgBot *telegram.Bot, l *slog.Logger) {
	l.Info("Планировщик ежедневных отчётов запущен")
	for {
		now := time.Now()
		if now.Hour() == 21 && now.Minute() == 0 {
			owners, err := userRepo.GetAllOwnersWithTelegram(context.Background())
			if err != nil {
				l.Error("Планировщик отчётов: не удалось получить владельцев", "error", err.Error())
			} else {
				for _, owner := range owners {
					stats, err := saleRepo.GetTodayTotal(context.Background(), owner.CompanyID)
					if err != nil {
						l.Error("Планировщик отчётов: не удалось получить статистику за день",
							"company_id", owner.CompanyID, "owner_id", owner.ID, "error", err.Error())
						continue
					}
					tgBot.SendDailyReport(owner.TgChatID, stats.Total, stats.Count)
				}
			}
			time.Sleep(61 * time.Second)
		}
		time.Sleep(30 * time.Second)
	}
}
