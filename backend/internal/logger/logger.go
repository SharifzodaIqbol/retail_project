package logger

import (
	"context"
	"log/slog"
	"os"
	"strings"
)

// L — глобальный логгер, инициализируется в Init(). Использовать напрямую
// можно там, где нет доступа к gin.Context (main.go, фоновые задачи).
var L *slog.Logger

// Init настраивает глобальный логгер на основе переменных окружения:
//   - LOG_LEVEL:  debug | info | warn | error (по умолчанию info)
//   - LOG_FORMAT: json | text (по умолчанию json; в проде нужен json)
//
// AddSource включён всегда — в логе ошибки сразу видно файл:строку,
// откуда она пришла, что сильно ускоряет дебаг в проде.
func Init() *slog.Logger {
	var level slog.Level
	switch strings.ToLower(os.Getenv("LOG_LEVEL")) {
	case "debug":
		level = slog.LevelDebug
	case "warn", "warning":
		level = slog.LevelWarn
	case "error":
		level = slog.LevelError
	default:
		level = slog.LevelInfo
	}

	opts := &slog.HandlerOptions{
		Level:     level,
		AddSource: true,
	}

	var handler slog.Handler
	if strings.ToLower(os.Getenv("LOG_FORMAT")) == "text" {
		handler = slog.NewTextHandler(os.Stdout, opts)
	} else {
		handler = slog.NewJSONHandler(os.Stdout, opts)
	}

	L = slog.New(handler)
	slog.SetDefault(L)
	return L
}

type ctxKey struct{}

// WithContext кладёт логгер (уже обогащённый, например, request_id) в context.Context.
func WithContext(ctx context.Context, l *slog.Logger) context.Context {
	return context.WithValue(ctx, ctxKey{}, l)
}

// FromContext достаёт логгер из контекста, либо возвращает глобальный логгер,
// либо — на самый крайний случай (Init не вызван, например в тестах) — slog.Default().
func FromContext(ctx context.Context) *slog.Logger {
	if l, ok := ctx.Value(ctxKey{}).(*slog.Logger); ok && l != nil {
		return l
	}
	if L != nil {
		return L
	}
	return slog.Default()
}
