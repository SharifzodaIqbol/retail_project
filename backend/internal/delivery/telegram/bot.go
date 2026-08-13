package telegram

import (
	"context"
	"fmt"
	"retail-managment-system/internal/logger"
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

func (b *Bot) Start(saleRepo *repository.SaleRepository, userRepo *repository.UserRepository, productRepo *repository.ProductRepository, debtorRepo *repository.DebtorRepository) {
	// Создаем меню
	menu := &telebot.ReplyMarkup{ResizeKeyboard: true}
	btnStats := menu.Text("📊 Даромади имрӯза")
	btnProfit := menu.Text("💰 Фоидаи соф")
	btnTop := menu.Text("🔝 Маҳсулотҳои бисер\nхарида шуда!")
	btnLowStock := menu.Text("⚠️ Тамом шуда истодааст")
	btnDebtors := menu.Text("📒 Китоби қарздорон")
	btnHelp := menu.Text("❓ Кӯмак")

	menu.Reply(
		menu.Row(btnStats, btnProfit),
		menu.Row(btnTop, btnLowStock),
		menu.Row(btnDebtors),
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
				logger.L.Warn("Telegram: не удалось привязать аккаунт по токену", "chat_id", c.Chat().ID, "error", err.Error())
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
		stats, err := saleRepo.GetTodayTotal(context.Background(), user.CompanyID)
		if err != nil {
			logger.L.Error("Telegram: ошибка получения выручки за день", "company_id", user.CompanyID, "error", err.Error())
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
		profit, err := saleRepo.GetDailyNetProfit(context.Background(), user.CompanyID)
		if err != nil {
			logger.L.Error("Telegram: ошибка расчёта чистой прибыли", "company_id", user.CompanyID, "error", err.Error())
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
		report, err := saleRepo.GetTopProducts(context.Background(), user.CompanyID, 5)
		if err != nil {
			logger.L.Error("Telegram: ошибка получения топа товаров", "company_id", user.CompanyID, "error", err.Error())
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
		products, err := productRepo.GetLowStockProductsByCompany(context.Background(), user.CompanyID, 10)
		if err != nil {
			logger.L.Error("Telegram: ошибка получения товаров с низким остатком", "company_id", user.CompanyID, "error", err.Error())
			return c.Send("❌ Хатогии базаи маълумот.")
		}
		if len(products) == 0 {
			return c.Send("✅ Миқдори ҳамаи маҳсулот кофӣ аст.")
		}
		msg := "🚨 **Маҳсулоти каммонда:**\n"
		for _, p := range products {
			unit := "дона"
			if p.Unit == "kg" {
				unit = "кг"
			}
			msg += fmt.Sprintf("• %s: **%g %s.**\n", p.Name, p.Stock, unit)
		}
		return c.Send(msg, telebot.ModeMarkdown)
	})

	// Кнопка: Список должников
	b.teleBot.Handle(&btnDebtors, func(c telebot.Context) error {
		user, err := userRepo.GetByChatID(context.Background(), c.Chat().ID)
		if err != nil || user.Role != "owner" {
			return c.Send("⛔ Танҳо соҳиби мағоза метавонад қарздоронро бубинад.")
		}
		debtors, err := debtorRepo.GetAllForTelegram(context.Background(), user.CompanyID)
		if err != nil {
			logger.L.Error("Telegram: ошибка получения списка должников", "company_id", user.CompanyID, "error", err.Error())
			return c.Send("❌ Хатогии базаи маълумот.")
		}
		if len(debtors) == 0 {
			return c.Send("✅ Ҳоло қарздорон нест.")
		}
		msg := "📒 *Рӯйхати қарздорон:*\n\n"
		totalAll := 0.0
		for i, d := range debtors {
			phone := ""
			if d.Phone != "" {
				phone = fmt.Sprintf(" · %s", d.Phone)
			}
			msg += fmt.Sprintf("%d. *%s*%s\n   💸 Қарз: *%.2f сомонӣ*\n\n", i+1, d.FullName, phone, d.TotalDebt)
			totalAll += d.TotalDebt
		}
		msg += fmt.Sprintf("━━━━━━━━━━━━━━━━\n💰 *Ҳамагӣ: %.2f сомонӣ*", totalAll)
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

func (b *Bot) SendCancelNotification(chatID int64, saleID int, reason string, total float64) {
	msg := fmt.Sprintf("⚠️ **БЕКОР КАРДАНИ ЧЕК!**\nЧек: №%d\nМаблағ: %.2f\nСабаб: %s", saleID, total, reason)
	if _, err := b.teleBot.Send(telebot.ChatID(chatID), msg, telebot.ModeMarkdown); err != nil {
		logger.L.Error("Telegram: не удалось отправить уведомление об отмене чека", "chat_id", chatID, "sale_id", saleID, "error", err.Error())
	}
}

func (b *Bot) SendDailyReport(chatID int64, totalDay float64, salesCount int) {
	msg := fmt.Sprintf("📊 **Натиҷаи рӯз**\n💰 Фурӯш: **%.2f сомонӣ**\n🧾 Миқдори чекҳо: **%d**", totalDay, salesCount)
	if _, err := b.teleBot.Send(telebot.ChatID(chatID), msg, telebot.ModeMarkdown); err != nil {
		logger.L.Error("Telegram: не удалось отправить ежедневный отчёт", "chat_id", chatID, "error", err.Error())
	}
}

func (b *Bot) SendProductEditNotification(chatID int64, sellerName, productName, reason string) {
	if sellerName == "" {
		sellerName = "Номаълум"
	}
	msg := fmt.Sprintf(
		"✏️ **Тағйироти маълумоти маҳсулот**\n👤 Фурушанда: %s\n🏷 Маҳсулот: %s\n📝 Сабаб: %s",
		sellerName, productName, reason,
	)
	if _, err := b.teleBot.Send(telebot.ChatID(chatID), msg, telebot.ModeMarkdown); err != nil {
		logger.L.Error("Telegram: не удалось отправить уведомление об изменении товара", "chat_id", chatID, "product", productName, "error", err.Error())
	}
}

func (b *Bot) SendInventoryChangeNotification(chatID int64, sellerName, productName string, addStock float64, reason string) {
	sign := "+"
	if addStock < 0 {
		sign = ""
	}
	if sellerName == "" {
		sellerName = "Номаълум"
	}
	msg := fmt.Sprintf(
		"📦 **Тағйироти склад**\n👤 Фурушанда: %s\n🏷 Маҳсулот: %s\n🔢 Тағйирот: %s%g\n📝 Сабаб: %s",
		sellerName, productName, sign, addStock, reason,
	)
	if _, err := b.teleBot.Send(telebot.ChatID(chatID), msg, telebot.ModeMarkdown); err != nil {
		logger.L.Error("Telegram: не удалось отправить уведомление об изменении склада", "chat_id", chatID, "product", productName, "error", err.Error())
	}
}
