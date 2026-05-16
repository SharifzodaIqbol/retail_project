package telegram

import (
	"context"
	"fmt"
	"retail-managment-system/internal/auth"
	"retail-managment-system/internal/repository"
	"time"

	"gopkg.in/telebot.v4"
)

type Bot struct {
	teleBot *telebot.Bot
}

func NewBot(token string) (*Bot, error) {
	pref := telebot.Settings{
		Token:  token,
		Poller: &telebot.LongPoller{Timeout: 10 * time.Second},
	}

	b, err := telebot.NewBot(pref)
	if err != nil {
		return nil, err
	}

	return &Bot{teleBot: b}, nil
}

func (b *Bot) Start(saleRepo *repository.SaleRepository, userRepo *repository.UserRepository, productRepo *repository.ProductRepository) {
	// Создаем меню
	menu := &telebot.ReplyMarkup{ResizeKeyboard: true}
	btnStats := menu.Text("📊 Выручка за сегодня")
	btnProfit := menu.Text("💰 Чистая прибыль")
	btnTop := menu.Text("🔝 Топ товаров")
	btnLowStock := menu.Text("⚠️ Заканчиваются")
	btnHelp := menu.Text("❓ Помощь")

	menu.Reply(
		menu.Row(btnStats, btnProfit),
		menu.Row(btnTop, btnLowStock),
		menu.Row(btnHelp),
	)

	// --- ОБРАБОТЧИКИ КОМАНД ---

	b.teleBot.Handle("/reg", func(c telebot.Context) error {
		args := c.Args()
		if len(args) < 2 {
			return c.Send("⚠️ Использование: `/reg логин пароль`", telebot.ModeMarkdown)
		}
		username, password := args[0], args[1]
		user, err := userRepo.GetByUsername(context.Background(), username)
		if err != nil || !auth.CheckPasswordHash(password, user.PasswordHash) {
			return c.Send("❌ Неверный логин или пароль.")
		}
		err = userRepo.UpdateChatID(context.Background(), username, c.Chat().ID)
		if err != nil {
			return c.Send("❌ Ошибка привязки.")
		}
		return c.Send(fmt.Sprintf("✅ Аккаунт **%s** привязан!", username), telebot.ModeMarkdown)
	})

	b.teleBot.Handle("/start", func(c telebot.Context) error {
		return c.Send("Привет! Для работы привяжите аккаунт через /reg", menu, telebot.ModeMarkdown)
	})

	// --- ОБРАБОТЧИКИ КНОПОК ---

	// Кнопка: Выручка
	b.teleBot.Handle(&btnStats, func(c telebot.Context) error {
		user, err := userRepo.GetByChatID(context.Background(), c.Chat().ID)
		if err != nil || user.Role != "owner" {
			return c.Send("⛔ Нет прав.")
		}
		stats, err := saleRepo.GetTodayTotal(context.Background())
		if err != nil {
			return c.Send("❌ Ошибка данных")
		}
		msg := fmt.Sprintf("📈 **Выручка за сегодня:** **%.2f сомони**", stats.Total)
		return c.Send(msg, telebot.ModeMarkdown)
	})

	// Кнопка: Чистая прибыль
	b.teleBot.Handle(&btnProfit, func(c telebot.Context) error {
		user, err := userRepo.GetByChatID(context.Background(), c.Chat().ID)
		if err != nil || user.Role != "owner" {
			return c.Send("⛔ У вас нет прав для просмотра прибыли.")
		}
		profit, err := saleRepo.GetDailyNetProfit(context.Background())
		if err != nil {
			return c.Send("❌ Ошибка расчета прибыли")
		}
		msg := fmt.Sprintf("💵 **Чистая прибыль сегодня:**\n**%.2f сомони**", profit)
		return c.Send(msg, telebot.ModeMarkdown)
	})

	// Кнопка: Топ товаров
	b.teleBot.Handle(&btnTop, func(c telebot.Context) error {
		user, err := userRepo.GetByChatID(context.Background(), c.Chat().ID)
		if err != nil || user.Role != "owner" {
			return c.Send("⛔ Нет прав.")
		}
		report, err := saleRepo.GetTopProducts(context.Background(), 5)
		if err != nil {
			return c.Send("❌ Ошибка получения топа")
		}
		return c.Send(report, telebot.ModeMarkdown)
	})

	// Кнопка: Заканчиваются товары
	b.teleBot.Handle(&btnLowStock, func(c telebot.Context) error {
		user, err := userRepo.GetByChatID(context.Background(), c.Chat().ID)
		if err != nil || user.Role != "owner" {
			return c.Send("⛔ Только владелец может видеть остатки.")
		}
		products, err := productRepo.GetLowStockProducts(context.Background(), 10)
		if err != nil {
			return c.Send("❌ Ошибка базы.")
		}
		if len(products) == 0 {
			return c.Send("✅ Всех товаров достаточно.")
		}
		msg := "🚨 **Заканчиваются:**\n"
		for _, p := range products {
			msg += fmt.Sprintf("• %s: **%d шт.**\n", p.Name, p.Stock)
		}
		return c.Send(msg, telebot.ModeMarkdown)
	})

	b.teleBot.Handle(&btnHelp, func(c telebot.Context) error {
		return c.Send("Для доступа к статистике привяжите аккаунт командой /reg логин пароль")
	})

	b.teleBot.Start()
}

// --- Уведомления ---

func (b *Bot) SendSaleNotification(chatID int64, saleID int, total float64) {
	msg := fmt.Sprintf("💰 **Новая продажа!**\nЧек: №%d\nСумма: **%.2f сомони**", saleID, total)
	b.teleBot.Send(telebot.ChatID(chatID), msg, telebot.ModeMarkdown)
}

func (b *Bot) SendCancelNotification(chatID int64, saleID int, reason string, total float64) {
	msg := fmt.Sprintf("⚠️ **ОТМЕНА ЧЕКА!**\nЧек: №%d\nСумма: %.2f\nПричина: %s", saleID, total, reason)
	b.teleBot.Send(telebot.ChatID(chatID), msg, telebot.ModeMarkdown)
}

func (b *Bot) SendDailyReport(chatID int64, totalDay float64, salesCount int) {
	msg := fmt.Sprintf("📊 **Итоги дня**\n💰 Выручка: **%.2f сомони**\n🧾 Чеков: **%d**", totalDay, salesCount)
	b.teleBot.Send(telebot.ChatID(chatID), msg, telebot.ModeMarkdown)
}
func (b *Bot) SendLowStockAlert(chatID int64, productName string, remainingStock int) {
	msg := fmt.Sprintf("⚠️ **ВНИМАНИЕ: ТОВАР ЗАКАНЧИВАЕТСЯ!**\n\n📦 Товар: %s\n📉 Осталось всего: **%d шт.**",
		productName, remainingStock)
	b.teleBot.Send(telebot.ChatID(chatID), msg, telebot.ModeMarkdown)
}
