package domain

import (
	"crypto/rand"
	"math/big"
)

const internalBarcodePrefix = "20"

func GenerateInternalEAN13() (string, error) {
	// 10 случайных цифр после префикса "20" -> 12 цифр, 13-я — контрольная.
	digits := make([]byte, 10)
	for i := range digits {
		n, err := rand.Int(rand.Reader, big.NewInt(10))
		if err != nil {
			return "", err
		}
		digits[i] = byte('0' + n.Int64())
	}
	body := internalBarcodePrefix + string(digits)
	return body + ean13CheckDigit(body), nil
}

// ean13CheckDigit считает контрольную цифру EAN-13 по стандартному
// алгоритму (нечётные позиции ×1, чётные ×3, считая с единицы слева).
func ean13CheckDigit(body12 string) string {
	sum := 0
	for i, c := range body12 {
		digit := int(c - '0')
		if i%2 == 0 {
			sum += digit
		} else {
			sum += digit * 3
		}
	}
	check := (10 - (sum % 10)) % 10
	return string(rune('0' + check))
}
