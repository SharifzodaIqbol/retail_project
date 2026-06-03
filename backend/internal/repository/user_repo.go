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

func (r *UserRepository) GetByUsername(ctx context.Context, username string) (*domain.User, error) {
	var u domain.User
	query := `SELECT id, company_id, username, password_hash, role FROM users WHERE username = $1`
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

// CreateWithPin — создание пользователя сразу с PIN
func (r *UserRepository) CreateWithPin(ctx context.Context, u domain.User) error {
	query := `INSERT INTO users (username, password_hash, pin_hash, role, company_id) VALUES ($1, $2, $3, $4, $5)`
	_, err := r.db.Exec(ctx, query, u.Username, u.PasswordHash, u.PinHash, u.Role, u.CompanyID)
	return err
}

func (r *UserRepository) Delete(ctx context.Context, id int) error {
	_, err := r.db.Exec(ctx, "DELETE FROM users WHERE id = $1", id)
	return err
}

// SetPin — установить/обновить PIN для конкретного пользователя
func (r *UserRepository) SetPin(ctx context.Context, userID int, pinHash string) error {
	_, err := r.db.Exec(ctx, `UPDATE users SET pin_hash = $1 WHERE id = $2`, pinHash, userID)
	return err
}

// GetPinHash — получить pin_hash пользователя по его ID (для проверки при входе)
func (r *UserRepository) GetPinHash(ctx context.Context, userID int) (string, error) {
	var pinHash string
	err := r.db.QueryRow(ctx, `SELECT COALESCE(pin_hash,'') FROM users WHERE id = $1`, userID).Scan(&pinHash)
	return pinHash, err
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

// GenerateTgLinkToken — создаёт одноразовый токен для привязки Telegram из приложения.
// Токен живёт 10 минут. Возвращает сгенерированный токен.
func (r *UserRepository) GenerateTgLinkToken(ctx context.Context, userID int) (string, error) {
	raw := make([]byte, 24)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	token := hex.EncodeToString(raw)

	_, err := r.db.Exec(ctx,
		`UPDATE users SET tg_link_token = $1, tg_link_token_at = NOW() WHERE id = $2`,
		token, userID,
	)
	if err != nil {
		return "", err
	}
	return token, nil
}

// ClaimTgLinkToken — проверяет токен (TTL 10 мин), привязывает chatID и сбрасывает токен.
func (r *UserRepository) ClaimTgLinkToken(ctx context.Context, token string, chatID int64) (*domain.User, error) {
	var u domain.User
	query := `
		UPDATE users
		SET tg_chat_id = $1, tg_link_token = NULL, tg_link_token_at = NULL
		WHERE tg_link_token = $2
		  AND tg_link_token_at > NOW() - INTERVAL '10 minutes'
		RETURNING id, company_id, username, role
	`
	err := r.db.QueryRow(ctx, query, chatID, token).
		Scan(&u.ID, &u.CompanyID, &u.Username, &u.Role)
	if err != nil {
		return nil, err
	}
	return &u, nil
}

// GetOwnerByCompany — возвращает владельца компании (нужен для Telegram уведомлений)
func (r *UserRepository) GetOwnerByCompany(ctx context.Context, companyID int) (*domain.User, error) {
	var u domain.User
	query := `SELECT id, username, COALESCE(tg_chat_id, 0) FROM users WHERE company_id = $1 AND role = 'owner' LIMIT 1`
	err := r.db.QueryRow(ctx, query, companyID).Scan(&u.ID, &u.Username, &u.TgChatID)
	return &u, err
}

// InvalidateTgLink — отвязывает Telegram от пользователя
func (r *UserRepository) InvalidateTgLink(ctx context.Context, userID int) error {
	_, err := r.db.Exec(ctx,
		`UPDATE users SET tg_chat_id = NULL, tg_link_token = NULL, tg_link_token_at = NULL WHERE id = $1`,
		userID,
	)
	return err
}

// GetTgLinkTokenAge — вспомогательный: проверяет, сколько секунд осталось до истечения токена
func (r *UserRepository) GetTgLinkTokenAge(ctx context.Context, userID int) (time.Duration, error) {
	var tokenAt *time.Time
	err := r.db.QueryRow(ctx, `SELECT tg_link_token_at FROM users WHERE id = $1`, userID).Scan(&tokenAt)
	if err != nil || tokenAt == nil {
		return 0, err
	}
	expires := tokenAt.Add(10 * time.Minute)
	remaining := time.Until(expires)
	if remaining < 0 {
		return 0, nil
	}
	return remaining, nil
}
