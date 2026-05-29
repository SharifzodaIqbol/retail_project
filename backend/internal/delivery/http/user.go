package http

import (
	"context"
	"log"
	"net/http"
	"retail-managment-system/internal/auth"
	"retail-managment-system/internal/domain"
	"strconv"

	"github.com/gin-gonic/gin"
)

func (h *Handler) getAllUsers(c *gin.Context) {
	list, err := h.userRepo.GetAll(context.Background())
	if err != nil {
		c.JSON(500, gin.H{"error": "Ошибка"})
		return
	}
	c.JSON(200, list)
}
func (h *Handler) createUser(c *gin.Context) {
	var req struct {
		Username string `json:"username" binding:"required"`
		Password string `json:"password" binding:"required"`
		Role     string `json:"role" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	ownerCompanyID, exists := c.Get("company_id")
	log.Println(ownerCompanyID)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Компания создателя не определена"})
		return
	}

	hash, _ := auth.HashPassword(req.Password)

	user := domain.User{
		Username:     req.Username,
		PasswordHash: hash,
		Role:         req.Role,
		CompanyID:    ownerCompanyID.(int),
	}

	if err := h.userRepo.Create(context.Background(), user); err != nil {
		c.JSON(500, gin.H{"error": "Ошибка создания пользователя"})
		return
	}
	c.JSON(200, gin.H{"status": "ok"})
}
func (h *Handler) deleteUser(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))
	if err := h.userRepo.Delete(context.Background(), id); err != nil {
		c.JSON(500, gin.H{"error": "Ошибка удаления"})
		return
	}
	c.JSON(200, gin.H{"status": "ok"})
}