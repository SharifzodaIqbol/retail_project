package repository

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type CompanyRepository struct {
	db *pgxpool.Pool
}

func NewCompanyRepository(db *pgxpool.Pool) *CompanyRepository {
	return &CompanyRepository{db: db}
}

// RegisterNewBusiness создает компанию (с 14 днями триала) и пользователя-owner в одной транзакции
func (r *CompanyRepository) RegisterNewBusiness(ctx context.Context, compName, username, passwordHash string) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	// 1. Создаем компанию с триалом на 14 дней
	var companyID int
	trialEndsAt := time.Now().Add(14 * 24 * time.Hour)
	err = tx.QueryRow(ctx,
		`INSERT INTO companies (name, billing_plan, trial_ends_at, is_paid) 
		 VALUES ($1, 'trial', $2, false) RETURNING id`,
		compName, trialEndsAt).Scan(&companyID)
	if err != nil {
		return err
	}

	// 2. Создаем пользователя с ролью 'owner', привязанного к этой компании
	_, err = tx.Exec(ctx,
		`INSERT INTO users (company_id, username, password_hash, role) 
		 VALUES ($1, $2, $3, 'owner')`,
		companyID, username, passwordHash)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}
