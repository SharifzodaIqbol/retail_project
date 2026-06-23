package repository

import "errors"

// ErrNotFound — возвращается, когда запись не найдена в рамках компании
// (используется в т.ч. для маскировки IDOR: чужой ID выглядит как "не найдено").
var ErrNotFound = errors.New("not found")
