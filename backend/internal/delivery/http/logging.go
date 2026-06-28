package http

import (
	"log/slog"
	"retail-managment-system/internal/logger"

	"github.com/gin-gonic/gin"
)

// reqLogger возвращает логгер, обогащённый контекстом текущего запроса:
// request_id (из middleware.RequestID) и, если уже установлены к этому
// моменту (после AuthMiddleware), company_id/user_id/role.
func reqLogger(c *gin.Context) *slog.Logger {
	l := logger.FromContext(c.Request.Context())
	if companyID, ok := c.Get("company_id"); ok {
		l = l.With("company_id", companyID)
	}
	if userID, ok := c.Get("user_id"); ok {
		l = l.With("user_id", userID)
	}
	if role, ok := c.Get("role"); ok {
		l = l.With("role", role)
	}
	return l.With("handler_path", c.FullPath(), "method", c.Request.Method)
}

// logErr логирует на уровне ERROR непредвиденную ошибку (БД, внешние сервисы,
// паника бизнес-логики и т.п.) перед тем, как отдать клиенту 5xx.
// msg — короткое описание места возникновения ("не удалось создать товар"),
// args — дополнительные key-value поля (id записи, company_id и т.д.).
func logErr(c *gin.Context, err error, msg string, args ...any) {
	l := reqLogger(c)
	if err != nil {
		args = append(args, "error", err.Error())
	}
	l.Error(msg, args...)
}

// logWarn — для ожидаемых "плохих", но не аварийных ситуаций: невалидный
// ввод, 404 по бизнес-причине, превышение лимита попыток и т.п. Не требует
// расследования само по себе, но полезно для аудита и обнаружения всплесков
// (например, массовых попыток подбора пароля/PIN).
func logWarn(c *gin.Context, msg string, args ...any) {
	reqLogger(c).Warn(msg, args...)
}
