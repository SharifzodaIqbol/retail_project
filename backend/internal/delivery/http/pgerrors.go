package http

import (
	"errors"

	"github.com/jackc/pgx/v5/pgconn"
)

// isUniqueViolation — true, если ошибка от БД — это нарушение уникального
// индекса/constraint'а (код 23505). Используется там, где клиент мог
// прислать штрихкод, который только что заняли параллельно (гонка между
// generateBarcode и фактическим сохранением, или два одновременных
// сохранения с одинаковым вручную введённым штрихкодом) — в этом случае
// нужно отдать понятный 409, а не общий 500, чтобы клиент показал
// продавцу осмысленное сообщение и предложил перегенерировать код.
func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		return pgErr.Code == "23505"
	}
	return false
}
