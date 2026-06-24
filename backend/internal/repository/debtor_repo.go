package repository

import (
	"context"
	"retail-managment-system/internal/domain"

	"github.com/jackc/pgx/v5/pgxpool"
)

type DebtorRepository struct {
	db *pgxpool.Pool
}

func NewDebtorRepository(db *pgxpool.Pool) *DebtorRepository {
	return &DebtorRepository{db: db}
}

// GetAll — список всех должников компании (только своя компания по company_id)
func (r *DebtorRepository) GetAll(ctx context.Context, companyID int) ([]domain.Debtor, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, company_id, full_name, COALESCE(phone,''), total_debt, updated_at
		FROM debtors
		WHERE company_id = $1
		ORDER BY updated_at DESC
	`, companyID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []domain.Debtor
	for rows.Next() {
		var d domain.Debtor
		if err := rows.Scan(&d.ID, &d.CompanyID, &d.FullName, &d.Phone, &d.TotalDebt, &d.UpdatedAt); err != nil {
			return nil, err
		}
		list = append(list, d)
	}
	if list == nil {
		list = []domain.Debtor{}
	}
	return list, nil
}

// GetByID — получить должника по id (с проверкой company_id — изоляция данных)
func (r *DebtorRepository) GetByID(ctx context.Context, id, companyID int) (*domain.Debtor, error) {
	var d domain.Debtor
	err := r.db.QueryRow(ctx, `
		SELECT id, company_id, full_name, COALESCE(phone,''), total_debt, updated_at
		FROM debtors
		WHERE id = $1 AND company_id = $2
	`, id, companyID).Scan(&d.ID, &d.CompanyID, &d.FullName, &d.Phone, &d.TotalDebt, &d.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &d, nil
}

// Create — добавить нового должника
func (r *DebtorRepository) Create(ctx context.Context, companyID int, req domain.CreateDebtorRequest) (*domain.Debtor, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	var d domain.Debtor
	err = tx.QueryRow(ctx, `
		INSERT INTO debtors (company_id, full_name, phone, total_debt, updated_at)
		VALUES ($1, $2, $3, $4, NOW())
		RETURNING id, company_id, full_name, COALESCE(phone,''), total_debt, updated_at
	`, companyID, req.FullName, req.Phone, req.InitialDebt).
		Scan(&d.ID, &d.CompanyID, &d.FullName, &d.Phone, &d.TotalDebt, &d.UpdatedAt)
	if err != nil {
		return nil, err
	}

	// Если начальный долг > 0 — записываем первую операцию в историю
	if req.InitialDebt > 0 {
		_, err = tx.Exec(ctx, `
			INSERT INTO debt_history (debtor_id, amount, type, note, created_at)
			VALUES ($1, $2, 'take', $3, NOW())
		`, d.ID, req.InitialDebt, req.Note)
		if err != nil {
			return nil, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return &d, nil
}

// AddOperation — добавить операцию (частичная оплата "pay" или новый долг "take")
// Возвращает обновлённого должника
func (r *DebtorRepository) AddOperation(ctx context.Context, debtorID, companyID int, req domain.DebtOperationRequest) (*domain.Debtor, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	// Проверяем принадлежность должника к компании (изоляция данных)
	var currentDebt float64
	err = tx.QueryRow(ctx,
		`SELECT total_debt FROM debtors WHERE id = $1 AND company_id = $2 FOR UPDATE`,
		debtorID, companyID,
	).Scan(&currentDebt)
	if err != nil {
		return nil, ErrNotFound
	}

	// Вычисляем новый итоговый долг
	var newDebt float64
	if req.Type == "pay" {
		newDebt = currentDebt - req.Amount
		if newDebt < 0 {
			newDebt = 0
		}
	} else {
		newDebt = currentDebt + req.Amount
	}

	// Обновляем долг
	var d domain.Debtor
	err = tx.QueryRow(ctx, `
		UPDATE debtors
		SET total_debt = $1, updated_at = NOW()
		WHERE id = $2 AND company_id = $3
		RETURNING id, company_id, full_name, COALESCE(phone,''), total_debt, updated_at
	`, newDebt, debtorID, companyID).
		Scan(&d.ID, &d.CompanyID, &d.FullName, &d.Phone, &d.TotalDebt, &d.UpdatedAt)
	if err != nil {
		return nil, err
	}

	// Записываем в историю
	_, err = tx.Exec(ctx, `
		INSERT INTO debt_history (debtor_id, amount, type, note, created_at)
		VALUES ($1, $2, $3, $4, NOW())
	`, debtorID, req.Amount, req.Type, req.Note)
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return &d, nil
}

// Delete — удалить должника (с проверкой company_id)
func (r *DebtorRepository) Delete(ctx context.Context, id, companyID int) error {
	result, err := r.db.Exec(ctx,
		`DELETE FROM debtors WHERE id = $1 AND company_id = $2`,
		id, companyID,
	)
	if err != nil {
		return err
	}
	if result.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// GetHistory — история операций по должнику (с проверкой company_id)
func (r *DebtorRepository) GetHistory(ctx context.Context, debtorID, companyID int) ([]domain.DebtHistory, error) {
	// Сначала убеждаемся, что должник принадлежит этой компании
	var exists bool
	err := r.db.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM debtors WHERE id = $1 AND company_id = $2)`,
		debtorID, companyID,
	).Scan(&exists)
	if err != nil || !exists {
		return nil, ErrNotFound
	}

	rows, err := r.db.Query(ctx, `
		SELECT id, debtor_id, amount, type, COALESCE(note,''), created_at
		FROM debt_history
		WHERE debtor_id = $1
		ORDER BY created_at DESC
	`, debtorID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []domain.DebtHistory
	for rows.Next() {
		var h domain.DebtHistory
		if err := rows.Scan(&h.ID, &h.DebtorID, &h.Amount, &h.Type, &h.Note, &h.CreatedAt); err != nil {
			return nil, err
		}
		list = append(list, h)
	}
	if list == nil {
		list = []domain.DebtHistory{}
	}
	return list, nil
}

// GetAllForTelegram — краткий список должников для Telegram (только с долгом > 0)
func (r *DebtorRepository) GetAllForTelegram(ctx context.Context, companyID int) ([]domain.Debtor, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, company_id, full_name, COALESCE(phone,''), total_debt, updated_at
		FROM debtors
		WHERE company_id = $1 AND total_debt > 0
		ORDER BY total_debt DESC
	`, companyID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []domain.Debtor
	for rows.Next() {
		var d domain.Debtor
		if err := rows.Scan(&d.ID, &d.CompanyID, &d.FullName, &d.Phone, &d.TotalDebt, &d.UpdatedAt); err != nil {
			return nil, err
		}
		list = append(list, d)
	}
	if list == nil {
		list = []domain.Debtor{}
	}
	return list, nil
}
