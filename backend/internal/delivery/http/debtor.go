package http

import (
	"context"
	"log"
	"net/http"
	"retail-managment-system/internal/domain"
	"retail-managment-system/internal/repository"
	"strconv"

	"github.com/gin-gonic/gin"
)

// getDebtors — GET /api/debtors
// Возвращает всех должников текущей компании
func (h *Handler) getDebtors(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	debtors, err := h.debtorRepo.GetAll(context.Background(), companyID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ошибка получения должников"})
		return
	}
	c.JSON(http.StatusOK, debtors)
}

// createDebtor — POST /api/debtors
// Добавить нового должника (owner или seller)
func (h *Handler) createDebtor(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)

	var req domain.CreateDebtorRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	debtor, err := h.debtorRepo.Create(context.Background(), companyID, req)
	if err != nil {
		log.Println(err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "не удалось создать должника"})
		return
	}
	c.JSON(http.StatusCreated, debtor)
}

// debtOperation — POST /api/debtors/:id/operation
// Частичная оплата ("pay") или добавление долга ("take")
func (h *Handler) debtOperation(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	debtorID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "неверный id"})
		return
	}

	var req domain.DebtOperationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	debtor, err := h.debtorRepo.AddOperation(context.Background(), debtorID, companyID, req)
	if err == repository.ErrNotFound {
		c.JSON(http.StatusNotFound, gin.H{"error": "должник не найден"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ошибка операции"})
		return
	}
	c.JSON(http.StatusOK, debtor)
}

// deleteDebtor — DELETE /api/debtors/:id
// Удалить должника (только owner)
func (h *Handler) deleteDebtor(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	debtorID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "неверный id"})
		return
	}

	if err := h.debtorRepo.Delete(context.Background(), debtorID, companyID); err == repository.ErrNotFound {
		c.JSON(http.StatusNotFound, gin.H{"error": "должник не найден"})
		return
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ошибка удаления"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// getDebtHistory — GET /api/debtors/:id/history
// История операций по должнику
func (h *Handler) getDebtHistory(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	debtorID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "неверный id"})
		return
	}

	history, err := h.debtorRepo.GetHistory(context.Background(), debtorID, companyID)
	if err == repository.ErrNotFound {
		c.JSON(http.StatusNotFound, gin.H{"error": "должник не найден"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ошибка получения истории"})
		return
	}
	c.JSON(http.StatusOK, history)
}
