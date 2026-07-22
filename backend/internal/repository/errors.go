package repository

import "errors"

// ErrNotFound — возвращается, когда запись не найдена в рамках компании
// (используется в т.ч. для маскировки IDOR: чужой ID выглядит как "не найдено").
var ErrNotFound = errors.New("not found")

// ErrInsufficientStock — возвращается из UpdateInventory, когда запрошенное
// уменьшение остатка (отрицательный add_stock) больше, чем реально есть на
// складе — т.е. итоговый stock ушёл бы в минус.
var ErrInsufficientStock = errors.New("insufficient stock")
