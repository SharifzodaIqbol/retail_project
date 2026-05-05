package repository

import (
	"context"
	"retail-managment-system/internal/domain"

	"github.com/jackc/pgx/v5/pgxpool"
)

type UserRepository struct {
	db *pgxpool.Pool
}

func NewUserRepository(db *pgxpool.Pool) *UserRepository {
	return &UserRepository{db: db}
}
func (r *UserRepository) GetByUsername(ctx context.Context, username string) (*domain.User, error) {
	var u domain.User
	query := `SELECT id, username, password_hash, role FROM users WHERE username = $1`
	err := r.db.QueryRow(ctx, query, username).Scan(&u.ID, &u.Username, &u.PasswordHash, &u.Role)
	return &u, err
}
func (r *UserRepository) Create(ctx context.Context, u domain.User) error {
	query := `INSERT INTO users (username, password_hash, role) VALUES ($1, $2, $3)`
	_, err := r.db.Exec(ctx, query, u.Username, u.PasswordHash, u.Role)
	return err
}
