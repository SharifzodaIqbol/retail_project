package repository

import (
	"context"
	"retail-managment-system/internal/domain"

	"github.com/jackc/pgx/v5/pgxpool"
)

type ProductUnitRepository struct {
	db *pgxpool.Pool
}

func NewProductUnitRepository(db *pgxpool.Pool) *ProductUnitRepository {
	return &ProductUnitRepository{db: db}
}

// GetForProducts — пакетно возвращает единицы продажи для набора товаров,
// сгруппированные по product_id. Используется там, где нужна полная
// карточка товара (поиск по имени, по штрихкоду) — избегаем N+1 запросов.
func (r *ProductUnitRepository) GetForProducts(ctx context.Context, companyID int, productIDs []int) (map[int][]domain.ProductUnit, error) {
	result := make(map[int][]domain.ProductUnit)
	if len(productIDs) == 0 {
		return result, nil
	}

	rows, err := r.db.Query(ctx, `
		SELECT id, company_id, product_id, label, conversion_factor, price, barcode, is_base, is_active
		FROM product_units
		WHERE company_id = $1 AND product_id = ANY($2) AND is_active = true
		ORDER BY is_base DESC, conversion_factor ASC`,
		companyID, productIDs,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var u domain.ProductUnit
		if err := rows.Scan(&u.ID, &u.CompanyID, &u.ProductID, &u.Label, &u.ConversionFactor, &u.Price, &u.Barcode, &u.IsBase, &u.IsActive); err != nil {
			return nil, err
		}
		result[u.ProductID] = append(result[u.ProductID], u)
	}
	return result, nil
}

// GetByID — единица продажи для оформления продажи. Скоуп по company_id
// обязателен: кассир не должен иметь возможность продать по unit_id,
// украденному у другой компании.
func (r *ProductUnitRepository) GetByID(ctx context.Context, companyID, unitID int) (*domain.ProductUnit, error) {
	var u domain.ProductUnit
	err := r.db.QueryRow(ctx, `
		SELECT id, company_id, product_id, label, conversion_factor, price, barcode, is_base, is_active
		FROM product_units WHERE id = $1 AND company_id = $2 AND is_active = true`,
		unitID, companyID,
	).Scan(&u.ID, &u.CompanyID, &u.ProductID, &u.Label, &u.ConversionFactor, &u.Price, &u.Barcode, &u.IsBase, &u.IsActive)
	if err != nil {
		return nil, err
	}
	return &u, nil
}

func (r *ProductUnitRepository) Create(ctx context.Context, companyID, productID int, req domain.CreateProductUnitRequest) (domain.ProductUnit, error) {
	var u domain.ProductUnit
	err := r.db.QueryRow(ctx, `
		INSERT INTO product_units (company_id, product_id, label, conversion_factor, price, barcode, is_base, is_active)
		VALUES ($1, $2, $3, $4, $5, $6, false, true)
		RETURNING id, company_id, product_id, label, conversion_factor, price, barcode, is_base, is_active`,
		companyID, productID, req.Label, req.ConversionFactor, req.Price, req.Barcode,
	).Scan(&u.ID, &u.CompanyID, &u.ProductID, &u.Label, &u.ConversionFactor, &u.Price, &u.Barcode, &u.IsBase, &u.IsActive)
	return u, err
}

// Update — редактирование единицы продажи. Базовую единицу (is_base) можно
// редактировать (например, поменять цену), но conversion_factor у неё
// остаётся защищённым запросом на уровне хендлера (см. http/product.go) —
// иначе можно было бы случайно испортить складской учёт, поменяв базовую
// единицу на "не 1 к 1".
func (r *ProductUnitRepository) Update(ctx context.Context, companyID, unitID int, req domain.CreateProductUnitRequest) error {
	tag, err := r.db.Exec(ctx, `
		UPDATE product_units
		SET label = $1, conversion_factor = $2, price = $3, barcode = $4
		WHERE id = $5 AND company_id = $6`,
		req.Label, req.ConversionFactor, req.Price, req.Barcode, unitID, companyID,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// Delete — мягкое удаление (is_active = false), не физическое. Единица
// могла уже фигурировать в исторических чеках (sale_items.unit_id), и
// удалять её физически нельзя — только скрыть из выбора кассира.
// Базовую единицу удалить нельзя вовсе (проверка на уровне хендлера).
func (r *ProductUnitRepository) Delete(ctx context.Context, companyID, unitID int) error {
	tag, err := r.db.Exec(ctx,
		`UPDATE product_units SET is_active = false WHERE id = $1 AND company_id = $2 AND is_base = false`,
		unitID, companyID,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
