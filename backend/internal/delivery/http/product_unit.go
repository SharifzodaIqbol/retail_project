package http

import (
	"context"
	"fmt"
	"net/http"
	"retail-managment-system/internal/domain"
	"retail-managment-system/internal/repository"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

// getProductUnits — GET /api/products/:id/units
func (h *Handler) getProductUnits(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	productID, _ := strconv.Atoi(c.Param("id"))

	unitsByProduct, err := h.productUnitRepo.GetForProducts(context.Background(), companyID, []int{productID})
	if err != nil {
		logErr(c, err, "Ошибка получения единиц продажи товара", "product_id", productID)
		c.JSON(500, gin.H{"error": "Ошибка получения единиц продажи"})
		return
	}
	c.JSON(200, unitsByProduct[productID])
}

// createProductUnit — POST /api/products/:id/units
// Добавляет новую единицу продажи товару (упаковка, блок, коробка...).
// Это НЕ создаёт базовую единицу — она уже существует с момента создания
// товара (см. ProductRepository.Create).
func (h *Handler) createProductUnit(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	productID, _ := strconv.Atoi(c.Param("id"))

	var req domain.CreateProductUnitRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}
	if req.Barcode != nil && strings.TrimSpace(*req.Barcode) == "" {
		req.Barcode = nil
	}

	count, err := h.productUnitRepo.CountExtraUnits(context.Background(), companyID, productID)
	if err != nil {
		logErr(c, err, "Создание единицы продажи: ошибка подсчёта существующих единиц", "product_id", productID)
		c.JSON(500, gin.H{"error": "Ошибка создания единицы продажи"})
		return
	}
	if count >= domain.MaxExtraUnitsPerProduct {
		c.JSON(400, gin.H{"error": fmt.Sprintf("Ҳадди аксар %d воҳиди иловагӣ барои як маҳсулот иҷозат дода мешавад", domain.MaxExtraUnitsPerProduct)})
		return
	}

	unit, err := h.productUnitRepo.Create(context.Background(), companyID, productID, req)
	if err != nil {
		if isUniqueViolation(err) {
			logWarn(c, "Создание единицы продажи: штрихкод уже занят", "product_id", productID)
			c.JSON(409, gin.H{"error": "Ин штрихкод аллакай истифода шудааст. Рамзи дигар созед"})
			return
		}
		logErr(c, err, "Ошибка создания единицы продажи", "product_id", productID)
		c.JSON(500, gin.H{"error": "Ошибка создания единицы продажи. Проверьте, не занят ли штрихкод"})
		return
	}
	c.JSON(http.StatusCreated, unit)
}

// updateProductUnit — PUT /api/products/:id/units/:unit_id
func (h *Handler) updateProductUnit(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	unitID, _ := strconv.Atoi(c.Param("unit_id"))

	var req domain.CreateProductUnitRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}
	if req.Barcode != nil && strings.TrimSpace(*req.Barcode) == "" {
		req.Barcode = nil
	}

	if err := h.productUnitRepo.Update(context.Background(), companyID, unitID, req); err != nil {
		if err == repository.ErrNotFound {
			c.JSON(404, gin.H{"error": "Единица продажи не найдена"})
			return
		}
		logErr(c, err, "Ошибка обновления единицы продажи", "unit_id", unitID)
		c.JSON(500, gin.H{"error": "Ошибка обновления единицы продажи"})
		return
	}
	c.JSON(200, gin.H{"status": "ok"})
}

// deleteProductUnit — DELETE /api/products/:id/units/:unit_id
// Базовую единицу удалить нельзя — без неё товар не имеет способа продажи
// "по умолчанию", и это сломало бы весь пересчёт склада.
func (h *Handler) deleteProductUnit(c *gin.Context) {
	companyID := c.MustGet("company_id").(int)
	unitID, _ := strconv.Atoi(c.Param("unit_id"))

	if err := h.productUnitRepo.Delete(context.Background(), companyID, unitID); err != nil {
		if err == repository.ErrNotFound {
			c.JSON(404, gin.H{"error": "Единица продажи не найдена или является базовой (её нельзя удалить)"})
			return
		}
		logErr(c, err, "Ошибка удаления единицы продажи", "unit_id", unitID)
		c.JSON(500, gin.H{"error": "Ошибка удаления единицы продажи"})
		return
	}
	c.JSON(200, gin.H{"status": "ok"})
}
