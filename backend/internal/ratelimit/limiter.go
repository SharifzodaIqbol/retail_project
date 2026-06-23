// Package ratelimit реализует простой in-memory rate limiter для защиты
// эндпоинтов входа (логин владельца, PIN-вход продавца) от подбора пароля/PIN.
//
// Используем счётчик неудачных попыток в скользящем окне: после N неудачных
// попыток за window — ключ блокируется на blockFor. Успешный вход сбрасывает
// счётчик. Реализация in-memory и не требует внешних зависимостей (Redis и
// т.п.) — этого достаточно для одного инстанса бэкенда; если в будущем
// появится несколько инстансов backend за балансировщиком, нужно будет
// перенести состояние в Redis, иначе лимиты не будут общими между инстансами.
package ratelimit

import (
	"sync"
	"time"
)

type entry struct {
	failures     int
	windowStart  time.Time
	blockedUntil time.Time
}

// Limiter — счётчик неудачных попыток по произвольному ключу
// (например "ip:1.2.3.4" или "ip:1.2.3.4:company:5:user:42").
type Limiter struct {
	mu          sync.Mutex
	entries     map[string]*entry
	maxAttempts int
	window      time.Duration
	blockFor    time.Duration
}

// New создаёт лимитер: maxAttempts неудачных попыток за window блокируют
// ключ на blockFor.
func New(maxAttempts int, window, blockFor time.Duration) *Limiter {
	l := &Limiter{
		entries:     make(map[string]*entry),
		maxAttempts: maxAttempts,
		window:      window,
		blockFor:    blockFor,
	}
	go l.cleanupLoop()
	return l
}

// Allowed проверяет, не заблокирован ли ключ сейчас. Не увеличивает счётчик —
// для этого используется RecordFailure после неудачной попытки.
func (l *Limiter) Allowed(key string) (allowed bool, retryAfter time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()

	e, ok := l.entries[key]
	if !ok {
		return true, 0
	}
	now := time.Now()
	if now.Before(e.blockedUntil) {
		return false, e.blockedUntil.Sub(now)
	}
	return true, 0
}

// RecordFailure фиксирует неудачную попытку. Если в текущем окне
// накопилось maxAttempts неудач — ключ блокируется на blockFor.
func (l *Limiter) RecordFailure(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := time.Now()
	e, ok := l.entries[key]
	if !ok || now.Sub(e.windowStart) > l.window {
		e = &entry{windowStart: now}
		l.entries[key] = e
	}
	e.failures++
	if e.failures >= l.maxAttempts {
		e.blockedUntil = now.Add(l.blockFor)
	}
}

// Reset сбрасывает счётчик неудач при успешном входе.
func (l *Limiter) Reset(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.entries, key)
}

// cleanupLoop периодически чистит старые записи, чтобы карта не росла
// бесконечно (например, при сканировании множества разных user_id/IP).
func (l *Limiter) cleanupLoop() {
	ticker := time.NewTicker(10 * time.Minute)
	defer ticker.Stop()
	for range ticker.C {
		l.mu.Lock()
		now := time.Now()
		for k, e := range l.entries {
			if now.After(e.blockedUntil) && now.Sub(e.windowStart) > l.window {
				delete(l.entries, k)
			}
		}
		l.mu.Unlock()
	}
}