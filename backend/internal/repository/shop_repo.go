package repository

import (
	"context"
	"retail-managment-system/internal/domain"

	"github.com/jackc/pgx/v5/pgxpool"
)

type ShopRepository struct {
	db *pgxpool.Pool
}

func NewShopRepository(db *pgxpool.Pool) *ShopRepository {
	return &ShopRepository{db: db}
}

func (r *ShopRepository) GetAllByCompany(ctx context.Context, companyID int) ([]domain.Shop, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id, company_id, name FROM shops WHERE company_id = $1 ORDER BY id`,
		companyID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var shops []domain.Shop
	for rows.Next() {
		var s domain.Shop
		if err := rows.Scan(&s.ID, &s.CompanyID, &s.Name); err != nil {
			return nil, err
		}
		shops = append(shops, s)
	}
	return shops, nil
}

// BelongsToCompany — проверяет, что магазин с данным id принадлежит компании.
// Используется при назначении сотрудника на магазин, чтобы владелец одной
// компании не мог назначить сотрудника на магазин чужой компании.
func (r *ShopRepository) BelongsToCompany(ctx context.Context, shopID int, companyID int) (bool, error) {
	var exists bool
	err := r.db.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM shops WHERE id = $1 AND company_id = $2)`,
		shopID, companyID,
	).Scan(&exists)
	return exists, err
}

func (r *ShopRepository) Create(ctx context.Context, companyID int, name string) (*domain.Shop, error) {
	var s domain.Shop
	err := r.db.QueryRow(ctx,
		`INSERT INTO shops (company_id, name) VALUES ($1, $2) RETURNING id, company_id, name`,
		companyID, name,
	).Scan(&s.ID, &s.CompanyID, &s.Name)
	return &s, err
}

func (r *ShopRepository) Delete(ctx context.Context, id int, companyID int) error {
	_, err := r.db.Exec(ctx,
		`DELETE FROM shops WHERE id = $1 AND company_id = $2`,
		id, companyID,
	)
	return err
}

func (r *ShopRepository) Update(ctx context.Context, id int, companyID int, name string) error {
	_, err := r.db.Exec(ctx,
		`UPDATE shops SET name = $1 WHERE id = $2 AND company_id = $3`,
		name, id, companyID,
	)
	return err
}
