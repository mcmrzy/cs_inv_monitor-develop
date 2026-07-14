package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// ParallelHandler 处理并联组相关的请求。
// 当前为占位实现，List 返回空列表避免前端 404，
// 其余方法返回 501 Not Implemented。
type ParallelHandler struct{}

func NewParallelHandler() *ParallelHandler {
	return &ParallelHandler{}
}

// List 返回空的并联组列表，让前端不报 404
func (h *ParallelHandler) List(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"code":    0,
		"message": "success",
		"data": gin.H{
			"items": []interface{}{},
			"total": 0,
		},
	})
}

// Get 返回单个并联组详情（未实现）
func (h *ParallelHandler) Get(c *gin.Context) {
	c.JSON(http.StatusNotImplemented, gin.H{
		"code":    501,
		"message": "not implemented",
	})
}

// Create 创建并联组（未实现）
func (h *ParallelHandler) Create(c *gin.Context) {
	c.JSON(http.StatusNotImplemented, gin.H{
		"code":    501,
		"message": "not implemented",
	})
}

// Update 更新并联组（未实现）
func (h *ParallelHandler) Update(c *gin.Context) {
	c.JSON(http.StatusNotImplemented, gin.H{
		"code":    501,
		"message": "not implemented",
	})
}

// Delete 删除并联组（未实现）
func (h *ParallelHandler) Delete(c *gin.Context) {
	c.JSON(http.StatusNotImplemented, gin.H{
		"code":    501,
		"message": "not implemented",
	})
}
