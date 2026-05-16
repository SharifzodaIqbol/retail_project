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

func (r *UserRepository) GetAll(ctx context.Context) ([]domain.User, error) {
	query := `SELECT id, username, role, COALESCE(tg_chat_id, 0) FROM users ORDER BY role, username`
	rows, err := r.db.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []domain.User
	for rows.Next() {
		var u domain.User
		if err := rows.Scan(&u.ID, &u.Username, &u.Role, &u.TgChatID); err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	return users, nil
}

func (r *UserRepository) Create(ctx context.Context, u domain.User) error {
	query := `INSERT INTO users (username, password_hash, role) VALUES ($1, $2, $3)`
	_, err := r.db.Exec(ctx, query, u.Username, u.PasswordHash, u.Role)
	return err
}

func (r *UserRepository) Delete(ctx context.Context, id int) error {
	_, err := r.db.Exec(ctx, "DELETE FROM users WHERE id = $1", id)
	return err
}

func (r *UserRepository) UpdateChatID(ctx context.Context, username string, chatID int64) error {
	query := `UPDATE users SET tg_chat_id = $1 WHERE username = $2`
	_, err := r.db.Exec(ctx, query, chatID, username)
	return err
}

func (r *UserRepository) GetByChatID(ctx context.Context, chatID int64) (domain.User, error) {
	var user domain.User
	query := `SELECT id, username, role, tg_chat_id FROM users WHERE tg_chat_id = $1`
	err := r.db.QueryRow(ctx, query, chatID).Scan(&user.ID, &user.Username, &user.Role, &user.TgChatID)
	return user, err
}

func (r *UserRepository) GetOwnerChatID(ctx context.Context) (int64, error) {
	var chatID int64
	query := `SELECT tg_chat_id FROM users WHERE role = 'owner' AND tg_chat_id IS NOT NULL LIMIT 1`
	err := r.db.QueryRow(ctx, query).Scan(&chatID)
	return chatID, err
}
