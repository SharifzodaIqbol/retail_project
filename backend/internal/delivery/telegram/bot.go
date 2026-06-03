package telegram

import (
	"context"
	"fmt"
	"retail-managment-system/internal/repository"
	"strings"
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
	btnStats := menu.Text("📊 Даромади имрӯза")
	btnProfit := menu.Text("💰 Фоидаи соф")
	btnTop := menu.Text("🔝 Маҳсулотҳои бисер\nхарида шуда!")
	btnLowStock := menu.Text("⚠️ Тамом шуда истодааст")
	btnHelp := menu.Text("❓ Кӯмак")

	menu.Reply(
		menu.Row(btnStats, btnProfit),
		menu.Row(btnTop, btnLowStock),
		menu.Row(btnHelp),
	)

	// --- ОБРАБОТЧИКИ КОМАНД ---

	// /start — с deeplink-токеном или без
	// Если /start TOKEN — автоматически привязывает аккаунт владельца
	b.teleBot.Handle("/start", func(c telebot.Context) error {
		args := c.Args()

		// Проверяем deeplink: /start <token>
		if len(args) == 1 {
			token := strings.TrimSpace(args[0])
			user, err := userRepo.ClaimTgLinkToken(context.Background(), token, c.Chat().ID)
			if err != nil {
				return c.Send("❌ Агар шумо аз акаунтатон бромада бошед, метавонед аз замимаи мобилӣ тавассути тугмаи «Пайваст кардани Telegram» истифода баред.")
			}
			return c.Send(
				fmt.Sprintf("✅ Аккаунт **%s** пайваст шуд ба Telegram!\n\nАкнун маълумотҳои хостаатонро метавонед ба даст оред!.", user.Username),
				menu,
				telebot.ModeMarkdown,
			)
		}

		// Обычный /start — показываем инструкцию
		return c.Send(
			"Салом! Барои кор бо бот аз замимаи мобилӣ тавассути тугмаи «Пайваст кардани Telegram» истифода баред.",
			menu,
			telebot.ModeMarkdown,
		)
	})

	// --- ОБРАБОТЧИКИ КНОПОК ---

	// Кнопка: Выручка
	b.teleBot.Handle(&btnStats, func(c telebot.Context) error {
		user, err := userRepo.GetByChatID(context.Background(), c.Chat().ID)
		if err != nil || user.Role != "owner" {
			return c.Send("⛔ Иҷозат нест.")
		}
		stats, err := saleRepo.GetTodayTotal(context.Background())
		if err != nil {
			return c.Send("❌ Хатогии маълумот")
		}
		msg := fmt.Sprintf("📈 **Даромади имруза:** **%.2f сомонӣ**", stats.Total)
		return c.Send(msg, telebot.ModeMarkdown)
	})

	// Кнопка: Чистая прибыль
	b.teleBot.Handle(&btnProfit, func(c telebot.Context) error {
		user, err := userRepo.GetByChatID(context.Background(), c.Chat().ID)
		if err != nil || user.Role != "owner" {
			return c.Send("⛔ Шумо иҷозати дидани фоида надоред.")
		}
		profit, err := saleRepo.GetDailyNetProfit(context.Background())
		if err != nil {
			return c.Send("❌ Хатогии ҳисобкунии фоида")
		}
		msg := fmt.Sprintf("💵 **Фоидаи соф имрӯз:**\n**%.2f сомонӣ**", profit)
		return c.Send(msg, telebot.ModeMarkdown)
	})

	// Кнопка: Топ товаров
	b.teleBot.Handle(&btnTop, func(c telebot.Context) error {
		user, err := userRepo.GetByChatID(context.Background(), c.Chat().ID)
		if err != nil || user.Role != "owner" {
			return c.Send("⛔ Иҷозат нест.")
		}
		report, err := saleRepo.GetTopProducts(context.Background(), 5)
		if err != nil {
			return c.Send("❌ Хато шуд барои дидани борҳои бисер харида шуда!")
		}
		return c.Send(report, telebot.ModeMarkdown)
	})

	// Кнопка: Заканчиваются товары
	b.teleBot.Handle(&btnLowStock, func(c telebot.Context) error {
		user, err := userRepo.GetByChatID(context.Background(), c.Chat().ID)
		if err != nil || user.Role != "owner" {
			return c.Send("⛔ Танҳо соҳиби мағоза метавонад боқимондаро бубинад.")
		}
		products, err := productRepo.GetLowStockProducts(context.Background(), 10)
		if err != nil {
			return c.Send("❌ Хатогии базаи маълумот.")
		}
		if len(products) == 0 {
			return c.Send("✅ Миқдори ҳамаи маҳсулот кофӣ аст.")
		}
		msg := "🚨 **Маҳсулоти каммонда:**\n"
		for _, p := range products {
			msg += fmt.Sprintf("• %s: **%d дона.**\n", p.Name, p.Stock)
		}
		return c.Send(msg, telebot.ModeMarkdown)
	})

	b.teleBot.Handle(&btnHelp, func(c telebot.Context) error {
		return c.Send(
			"Барои дастрасӣ ба омор профили худро аз замимаи мобилӣ тавассути тугмаи «Пайваст кардани Telegram» истифода баред.",
			telebot.ModeMarkdown,
		)
	})

	b.teleBot.Start()
}

// --- Уведомления ---

func (b *Bot) SendSaleNotification(chatID int64, saleID int, total float64) {
	msg := fmt.Sprintf("💰 **Фурӯши нав!**\nЧек: №%d\nМаблағ **%.2f сомонӣ**", saleID, total)
	b.teleBot.Send(telebot.ChatID(chatID), msg, telebot.ModeMarkdown)
}

func (b *Bot) SendCancelNotification(chatID int64, saleID int, reason string, total float64) {
	msg := fmt.Sprintf("⚠️ **БЕКОР КАРДАНИ ЧЕК!**\nЧек: №%d\nМаблағ: %.2f\nСабаб: %s", saleID, total, reason)
	b.teleBot.Send(telebot.ChatID(chatID), msg, telebot.ModeMarkdown)
}

func (b *Bot) SendDailyReport(chatID int64, totalDay float64, salesCount int) {
	msg := fmt.Sprintf("📊 **Натиҷаи рӯз**\n💰 Фурӯш: **%.2f сомонӣ**\n🧾 Миқдори чекҳо: **%d**", totalDay, salesCount)
	b.teleBot.Send(telebot.ChatID(chatID), msg, telebot.ModeMarkdown)
}

func (b *Bot) SendLowStockAlert(chatID int64, productName string, remainingStock int) {
	msg := fmt.Sprintf("⚠️ **ДИҚҚАТ: МАҲСУЛОТ КАМ МОНД!**\n\n📦 Маҳсулот: %s\n📉 Танҳо фурӯхта шуд: **%d дона**",
		productName, remainingStock)
	b.teleBot.Send(telebot.ChatID(chatID), msg, telebot.ModeMarkdown)
}
