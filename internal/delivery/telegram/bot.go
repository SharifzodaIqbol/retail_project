package telegram

import (
	"context"
	"fmt"
	"log"
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

func (b *Bot) Start(saleRepo *repository.SaleRepository, userRepo *repository.UserRepository) {
	menu := &telebot.ReplyMarkup{ResizeKeyboard: true}
	btnStats := menu.Text("📊 Выручка за сегодня")
	btnHelp := menu.Text("❓ Помощь")
	btnTop := menu.Text("🔝 Топ товаров")
	menu.Reply(
		menu.Row(btnStats),
		menu.Row(btnHelp, btnTop), // Поставим в один ряд для красоты
	)

	// 1. Команда привязки аккаунта
	// В bot.go, внутри метода Start
	b.teleBot.Handle("/reg", func(c telebot.Context) error {
		args := c.Args()
		// 1. Проверяем, что передали и логин, и пароль
		if len(args) < 2 {
			return c.Send("⚠️ Использование: `/reg логин пароль`\nПример: `/reg boss qwerty123`", telebot.ModeMarkdown)
		}

		username := args[0]
		password := args[1]

		// 2. Ищем пользователя в базе (так же, как при логине)
		user, err := userRepo.GetByUsername(context.Background(), username)

		if err != nil || !auth.CheckPasswordHash(password, user.PasswordHash) {
			return c.Send("❌ Неверный логин или пароль.")
		}

		if user.TgChatID != 0 && user.TgChatID != c.Chat().ID {
			return c.Send("⛔ Этот аккаунт уже привязан к другому устройству. Если это ошибка, обратитесь к программисту для сброса.")
		}

		err = userRepo.UpdateChatID(context.Background(), username, c.Chat().ID)
		if err != nil {
			return c.Send("❌ Ошибка привязки. База данных недоступна.")
		}

		return c.Send(fmt.Sprintf("✅ Аккаунт **%s** успешно привязан!\n\n*В целях безопасности удалите свое сообщение с паролем из этого чата.*", username), telebot.ModeMarkdown)
	})

	// 2. Обычный старт
	b.teleBot.Handle("/start", func(c telebot.Context) error {
		return c.Send("Привет! Если вы владелец магазина, привяжите аккаунт командой: `/reg ваш_логин`", menu, telebot.ModeMarkdown)
	})

	// 3. Защищенная кнопка "Выручка"
	b.teleBot.Handle(&btnStats, func(c telebot.Context) error {
		// ПРОВЕРКА ПРАВ: Кто нажал кнопку?
		user, err := userRepo.GetByChatID(context.Background(), c.Chat().ID)
		if err != nil || user.Role != "owner" { // Убедись, что в БД у хозяина роль "owner", а не "seller"
			return c.Send("⛔ У вас нет прав для просмотра выручки.")
		}

		total, err := saleRepo.GetTodayTotal(context.Background())
		if err != nil {
			log.Printf("Ошибка получения статистики: %v", err)
			return c.Send("❌ Ошибка при получении данных")
		}

		msg := fmt.Sprintf("📈 **Отчет за сегодня (%s):**\n\n💰 Итоговая выручка: **%.2f сомони**",
			time.Now().Format("02.01.2006"), total)
		return c.Send(msg, telebot.ModeMarkdown)
	})

	// 4. Защищенная кнопка "Топ"
	b.teleBot.Handle(&btnTop, func(c telebot.Context) error {
		// ПРОВЕРКА ПРАВ
		user, err := userRepo.GetByChatID(context.Background(), c.Chat().ID)
		if err != nil || user.Role != "owner" {
			return c.Send("⛔ У вас нет прав для просмотра топа товаров.")
		}

		report, err := saleRepo.GetTopProducts(context.Background(), 5)
		if err != nil {
			return c.Send("❌ Ошибка получения топа")
		}
		return c.Send(report, telebot.ModeMarkdown)
	})

	b.teleBot.Handle(&btnHelp, func(c telebot.Context) error {
		return c.Send("Я бизнес-ассистент. Для доступа к кнопкам нужно быть владельцем и привязать аккаунт через /reg.")
	})

	b.teleBot.Start()
}

// Функции отправки уведомлений остаются без изменений
func (b *Bot) SendSaleNotification(chatID int64, saleID int, total float64) {
	msg := fmt.Sprintf("💰 **Новая продажа!**\nЧек: №%d\nСумма: **%.2f сомони**", saleID, total)
	b.teleBot.Send(telebot.ChatID(chatID), msg, telebot.ModeMarkdown)
}

func (b *Bot) SendCancelNotification(chatID int64, saleID int, reason string, total float64) {
	msg := fmt.Sprintf("⚠️ **ВНИМАНИЕ: ОТМЕНА ЧЕКА!**\nЧек: №%d\nСумма: %.2f\nПричина: %s", saleID, total, reason)
	b.teleBot.Send(telebot.ChatID(chatID), msg, telebot.ModeMarkdown)
}
