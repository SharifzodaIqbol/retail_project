package http

import (
	"context"
	"net/http"
	"retail-managment-system/internal/domain"
	"retail-managment-system/internal/repository"
	"strconv"

	"github.com/gin-gonic/gin"
)

// getDebtors — GET /api/debtors?page=1&limit=50
// Возвращает страницу должников текущей компании. Параметры: page (с 1), limit (макс. 200).
func (h *Handler) getDebtors(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	shopID := c.MustGet("shop_id").(int)

	page, limit := parsePagination(c, 50, 200)
	offset := (page - 1) * limit

	debtors, total, err := h.debtorRepo.GetAll(context.Background(), companyID, shopID, limit, offset)
	if err != nil {
		logErr(c, err, "Ошибка получения списка должников", "company_id", companyID)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ошибка получения должников"})
		return
	}
	c.JSON(http.StatusOK, buildPage(debtors, total, page, limit))
}

// createDebtor — POST /api/debtors
// Добавить нового должника (owner или seller)
func (h *Handler) createDebtor(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	shopID := c.MustGet("shop_id").(int)

	var req domain.CreateDebtorRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	debtor, err := h.debtorRepo.Create(context.Background(), companyID, shopID, req)
	if err != nil {
		logErr(c, err, "Ошибка создания должника", "company_id", companyID)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "не удалось создать должника"})
		return
	}
	c.JSON(http.StatusCreated, debtor)
}

// debtOperation — POST /api/debtors/:id/operation
// Частичная оплата ("pay") или добавление долга ("take")
func (h *Handler) debtOperation(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	shopID := c.MustGet("shop_id").(int)
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

	debtor, err := h.debtorRepo.AddOperation(context.Background(), debtorID, companyID, shopID, req)
	if err == repository.ErrNotFound {
		logWarn(c, "Операция по должнику: должник не найден", "debtor_id", debtorID, "company_id", companyID)
		c.JSON(http.StatusNotFound, gin.H{"error": "должник не найден"})
		return
	}
	if err != nil {
		logErr(c, err, "Ошибка выполнения операции по должнику", "debtor_id", debtorID, "company_id", companyID)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ошибка операции"})
		return
	}
	c.JSON(http.StatusOK, debtor)
}

// deleteDebtor — DELETE /api/debtors/:id
// Удалить должника (только owner)
func (h *Handler) deleteDebtor(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	shopID := c.MustGet("shop_id").(int)
	debtorID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "неверный id"})
		return
	}

	if err := h.debtorRepo.Delete(context.Background(), debtorID, companyID, shopID); err == repository.ErrNotFound {
		logWarn(c, "Удаление должника: не найден", "debtor_id", debtorID, "company_id", companyID)
		c.JSON(http.StatusNotFound, gin.H{"error": "должник не найден"})
		return
	} else if err != nil {
		logErr(c, err, "Ошибка удаления должника", "debtor_id", debtorID, "company_id", companyID)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ошибка удаления"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// getDebtHistory — GET /api/debtors/:id/history
// История операций по должнику
func (h *Handler) getDebtHistory(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	shopID := c.MustGet("shop_id").(int)
	debtorID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "неверный id"})
		return
	}

	history, err := h.debtorRepo.GetHistory(context.Background(), debtorID, companyID, shopID)
	if err == repository.ErrNotFound {
		logWarn(c, "История должника: должник не найден", "debtor_id", debtorID, "company_id", companyID)
		c.JSON(http.StatusNotFound, gin.H{"error": "должник не найден"})
		return
	}
	if err != nil {
		logErr(c, err, "Ошибка получения истории должника", "debtor_id", debtorID, "company_id", companyID)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ошибка получения истории"})
		return
	}
	c.JSON(http.StatusOK, history)
}
