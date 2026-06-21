package repository

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"retail-managment-system/internal/domain"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type UserRepository struct {
	db *pgxpool.Pool
}

func NewUserRepository(db *pgxpool.Pool) *UserRepository {
	return &UserRepository{db: db}
}

// GetByUsername — ищет пользователя глобально (для логина owner'а).
// Возвращает ТОЛЬКО owner'ов — продавцы через логин/пароль не входят.
func (r *UserRepository) GetByUsername(ctx context.Context, username string) (*domain.User, error) {
	var u domain.User
	query := `SELECT id, company_id, username, password_hash, role FROM users WHERE username = $1 AND role = 'owner'`
	err := r.db.QueryRow(ctx, query, username).Scan(&u.ID, &u.CompanyID, &u.Username, &u.PasswordHash, &u.Role)
	return &u, err
}

// GetByUsernameAndCompany — поиск с учётом company_id (нужен для PIN-логина)
func (r *UserRepository) GetByUsernameAndCompany(ctx context.Context, username string, companyID int) (*domain.User, error) {
	var u domain.User
	query := `SELECT id, company_id, username, password_hash, COALESCE(pin_hash,''), role FROM users WHERE username = $1 AND company_id = $2`
	err := r.db.QueryRow(ctx, query, username, companyID).Scan(
		&u.ID, &u.CompanyID, &u.Username, &u.PasswordHash, &u.PinHash, &u.Role,
	)
	return &u, err
}

func (r *UserRepository) GetAll(ctx context.Context) ([]domain.User, error) {
	query := `SELECT id, username, role, COALESCE(tg_chat_id, 0), (pin_hash IS NOT NULL AND pin_hash != '') FROM users ORDER BY role, username`
	rows, err := r.db.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []domain.User
	for rows.Next() {
		var u domain.User
		if err := rows.Scan(&u.ID, &u.Username, &u.Role, &u.TgChatID, &u.HasPin); err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	return users, nil
}

// GetAllByCompany — возвращает только сотрудников указанной компании
func (r *UserRepository) GetAllByCompany(ctx context.Context, companyID int) ([]domain.User, error) {
	query := `SELECT id, username, role, COALESCE(tg_chat_id, 0), (pin_hash IS NOT NULL AND pin_hash != '') FROM users WHERE company_id = $1 ORDER BY role, username`
	rows, err := r.db.Query(ctx, query, companyID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []domain.User
	for rows.Next() {
		var u domain.User
		if err := rows.Scan(&u.ID, &u.Username, &u.Role, &u.TgChatID, &u.HasPin); err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	return users, nil
}

// GetByID — получить пользователя по ID (используется после PIN-проверки)
func (r *UserRepository) GetByID(ctx context.Context, id int) (*domain.User, error) {
	var u domain.User
	query := `SELECT id, company_id, username, role FROM users WHERE id = $1`
	err := r.db.QueryRow(ctx, query, id).Scan(&u.ID, &u.CompanyID, &u.Username, &u.Role)
	return &u, err
}

// GetByIDAndCompany — получить пользователя по ID с проверкой company_id (безопасность)
func (r *UserRepository) GetByIDAndCompany(ctx context.Context, id int, companyID int) (*domain.User, error) {
	var u domain.User
	query := `SELECT id, company_id, username, COALESCE(pin_hash,''), role FROM users WHERE id = $1 AND company_id = $2`
	err := r.db.QueryRow(ctx, query, id, companyID).Scan(&u.ID, &u.CompanyID, &u.Username, &u.PinHash, &u.Role)
	return &u, err
}

func (r *UserRepository) Create(ctx context.Context, u domain.User) error {
	query := `INSERT INTO users (username, password_hash, role, company_id) VALUES ($1, $2, $3, $4)`
	_, err := r.db.Exec(ctx, query, u.Username, u.PasswordHash, u.Role, u.CompanyID)
	return err
}

// CreateWithPin — создание пользователя сразу с PIN (без пароля для seller'а)
func (r *UserRepository) CreateWithPin(ctx context.Context, u domain.User) error {
	query := `INSERT INTO users (username, password_hash, pin_hash, role, company_id) VALUES ($1, $2, $3, $4, $5)`
	_, err := r.db.Exec(ctx, query, u.Username, u.PasswordHash, u.PinHash, u.Role, u.CompanyID)
	return err
}

// CreateSeller — создание продавца без пароля (только PIN)
func (r *UserRepository) CreateSeller(ctx context.Context, u domain.User) error {
	query := `INSERT INTO users (username, password_hash, pin_hash, role, company_id) VALUES ($1, '', $2, $3, $4)`
	_, err := r.db.Exec(ctx, query, u.Username, u.PinHash, u.Role, u.CompanyID)
	return err
}

func (r *UserRepository) Delete(ctx context.Context, id int) error {
	_, err := r.db.Exec(ctx, `DELETE FROM users WHERE id = $1`, id)
	return err
}

func (r *UserRepository) GetPinHash(ctx context.Context, userID int) (string, error) {
	var pinHash string
	err := r.db.QueryRow(ctx, `SELECT COALESCE(pin_hash, '') FROM users WHERE id = $1`, userID).Scan(&pinHash)
	return pinHash, err
}

func (r *UserRepository) SetPin(ctx context.Context, userID int, pinHash string) error {
	_, err := r.db.Exec(ctx, `UPDATE users SET pin_hash = $1 WHERE id = $2`, pinHash, userID)
	return err
}

func (r *UserRepository) GenerateTgLinkToken(ctx context.Context, userID int) (string, error) {
	b := make([]byte, 16)
	_, err := rand.Read(b)
	if err != nil {
		return "", err
	}
	token := hex.EncodeToString(b)
	expiresAt := time.Now().Add(10 * time.Minute)
	_, err = r.db.Exec(ctx,
		`UPDATE users SET tg_link_token = $1, tg_link_token_expires_at = $2 WHERE id = $3`,
		token, expiresAt, userID,
	)
	return token, err
}

func (r *UserRepository) GetByTgLinkToken(ctx context.Context, token string) (*domain.User, error) {
	var u domain.User
	err := r.db.QueryRow(ctx,
		`SELECT id, company_id, username, role FROM users WHERE tg_link_token = $1 AND tg_link_token_expires_at > NOW()`,
		token,
	).Scan(&u.ID, &u.CompanyID, &u.Username, &u.Role)
	return &u, err
}

func (r *UserRepository) SetTgChatID(ctx context.Context, userID int, chatID int64) error {
	_, err := r.db.Exec(ctx,
		`UPDATE users SET tg_chat_id = $1, tg_link_token = NULL, tg_link_token_expires_at = NULL WHERE id = $2`,
		chatID, userID,
	)
	return err
}

func (r *UserRepository) InvalidateTgLink(ctx context.Context, userID int) error {
	_, err := r.db.Exec(ctx,
		`UPDATE users SET tg_chat_id = NULL, tg_link_token = NULL, tg_link_token_expires_at = NULL WHERE id = $1`,
		userID,
	)
	return err
}

func (r *UserRepository) GetOwnerChatID(ctx context.Context, companyID int) (int64, error) {
	var chatID int64
	query := `SELECT tg_chat_id FROM users WHERE role = 'owner' AND company_id = $1 AND tg_chat_id IS NOT NULL LIMIT 1`
	err := r.db.QueryRow(ctx, query, companyID).Scan(&chatID)
	return chatID, err
}
func (r *UserRepository) GetByChatID(ctx context.Context, chatID int64) (domain.User, error) {
	var user domain.User
	query := `SELECT id, username, role, tg_chat_id FROM users WHERE tg_chat_id = $1`
	err := r.db.QueryRow(ctx, query, chatID).Scan(&user.ID, &user.Username, &user.Role, &user.TgChatID)
	return user, err
}
func (r *UserRepository) ClaimTgLinkToken(ctx context.Context, token string, chatID int64) (*domain.User, error) {
	var u domain.User
	query := `
		UPDATE users
		SET tg_chat_id = $1, tg_link_token = NULL, tg_link_token_expires_at = NULL
		WHERE tg_link_token = $2
		  AND tg_link_token_expires_at > NOW()
		RETURNING id, company_id, username, role
	`
	err := r.db.QueryRow(ctx, query, chatID, token).
		Scan(&u.ID, &u.CompanyID, &u.Username, &u.Role)
	if err != nil {
		return nil, err
	}
	return &u, nil
}
