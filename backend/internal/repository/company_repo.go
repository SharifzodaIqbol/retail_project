package repository

import (
	"context"
	"fmt"
	"retail-managment-system/internal/domain"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type CompanyRepository struct {
	db *pgxpool.Pool
}

func NewCompanyRepository(db *pgxpool.Pool) *CompanyRepository {
	return &CompanyRepository{db: db}
}

// CheckTrialEligibility — проверяет, может ли устройство/телефон получить триал
func (r *CompanyRepository) CheckTrialEligibility(
	ctx context.Context,
	deviceID string,
	phone string,
) (domain.TrialCheckResult, error) {

	// Проверка 1: устройство уже использовало триал?
	if deviceID != "" && deviceID != "unknown" {
		var existingCompanyID int
		err := r.db.QueryRow(ctx,
			`SELECT company_id FROM trial_devices WHERE device_id = $1`,
			deviceID,
		).Scan(&existingCompanyID)

		if err == nil {
			// Запись найдена — устройство уже регистрировалось
			return domain.TrialCheckResult{
				Allowed: false,
				Reason:  domain.TrialDeniedDevice,
			}, nil
		}
		// pgx возвращает pgx.ErrNoRows если не найдено — это нормально, продолжаем
	}

	// Проверка 2: номер телефона уже верифицирован под другой компанией?
	if phone != "" {
		var existingCompanyID int
		err := r.db.QueryRow(ctx,
			`SELECT id FROM companies 
             WHERE owner_phone = $1 AND is_phone_verified = true`,
			phone,
		).Scan(&existingCompanyID)

		if err == nil {
			return domain.TrialCheckResult{
				Allowed: false,
				Reason:  domain.TrialDeniedPhone,
			}, nil
		}
	}

	return domain.TrialCheckResult{Allowed: true}, nil
}

// RegisterNewBusiness — обновлённая версия с проверкой триала
func (r *CompanyRepository) RegisterNewBusiness(
	ctx context.Context,
	compName, username, passwordHash, deviceID, phone string,
) error {
	// Сначала проверяем право на триал
	check, err := r.CheckTrialEligibility(ctx, deviceID, phone)
	if err != nil {
		return fmt.Errorf("ошибка проверки триала: %w", err)
	}
	if !check.Allowed {
		// Возвращаем специфичную ошибку — хэндлер выдаст 409 с причиной
		return &TrialNotAllowedError{Reason: check.Reason}
	}

	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var companyID int
	trialEndsAt := time.Now().Add(14 * 24 * time.Hour)
	err = tx.QueryRow(ctx,
		`INSERT INTO companies (name, billing_plan, trial_ends_at, is_paid, owner_phone) 
         VALUES ($1, 'trial', $2, false, NULLIF($3, '')) RETURNING id`,
		compName, trialEndsAt, phone,
	).Scan(&companyID)
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx,
		`INSERT INTO users (company_id, username, password_hash, role) 
         VALUES ($1, $2, $3, 'owner')`,
		companyID, username, passwordHash,
	)
	if err != nil {
		return err
	}

	// Сохраняем device_id — даже если пустой, пишем только если есть
	if deviceID != "" && deviceID != "unknown" {
		_, err = tx.Exec(ctx,
			`INSERT INTO trial_devices (device_id, company_id) VALUES ($1, $2)`,
			deviceID, companyID,
		)
		if err != nil {
			return err // если уже есть — транзакция откатится
		}
	}

	return tx.Commit(ctx)
}

// GetByID — получить компанию по ID (используется при логине для названия)
func (r *CompanyRepository) GetByID(ctx context.Context, id int) (*domain.Company, error) {
	var c domain.Company
	err := r.db.QueryRow(ctx,
		`SELECT id, name FROM companies WHERE id = $1`, id,
	).Scan(&c.ID, &c.Name)
	return &c, err
}

// Typed error для хэндлера
type TrialNotAllowedError struct {
	Reason domain.TrialDeniedReason
}

func (e *TrialNotAllowedError) Error() string {
	return fmt.Sprintf("trial not allowed: %s", e.Reason)
}
