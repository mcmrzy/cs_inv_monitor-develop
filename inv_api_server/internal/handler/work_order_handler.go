package handler

// TODO: WorkOrder handler is a stub implementation. All endpoints return hardcoded/fake data.
// This needs to be implemented with a proper repository layer and database operations.

import (
	"log"
	"strconv"

	"inv-api-server/pkg/apperr"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

type WorkOrderHandler struct{}

func NewWorkOrderHandler() *WorkOrderHandler {
	return &WorkOrderHandler{}
}

func (h *WorkOrderHandler) List(c *gin.Context) {
	log.Printf("WARNING: work_order_handler.List is using stub implementation")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	response.Page(c, []interface{}{}, 0, page, pageSize)
}

func (h *WorkOrderHandler) GetByID(c *gin.Context) {
	log.Printf("WARNING: work_order_handler.GetByID is using stub implementation")
	orderID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("invalid order id"))
		return
	}

	response.Success(c, gin.H{
		"id":           orderID,
		"title":        "示例工单",
		"description":  "工单描述",
		"status":       "pending",
		"priority":     "normal",
		"device_sn":    "SN001",
		"created_at":   "2024-01-01 00:00:00",
		"assigned_to":  nil,
	})
}

func (h *WorkOrderHandler) GetStatistics(c *gin.Context) {
	log.Printf("WARNING: work_order_handler.GetStatistics is using stub implementation")
	response.Success(c, gin.H{
		"total":    0,
		"pending":  0,
		"processing": 0,
		"completed": 0,
		"cancelled": 0,
	})
}

func (h *WorkOrderHandler) Create(c *gin.Context) {
	log.Printf("WARNING: work_order_handler.Create is using stub implementation")
	var req struct {
		Title       string `json:"title" binding:"required"`
		Description string `json:"description"`
		Priority    string `json:"priority"`
		DeviceSN    string `json:"device_sn"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	response.SuccessWithMessage(c, "work order created", gin.H{"id": 1})
}

func (h *WorkOrderHandler) Update(c *gin.Context) {
	log.Printf("WARNING: work_order_handler.Update is using stub implementation")
	orderID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("invalid order id"))
		return
	}

	var req struct {
		Title       string `json:"title"`
		Description string `json:"description"`
		Status      string `json:"status"`
		Priority    string `json:"priority"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	response.SuccessWithMessage(c, "work order updated", gin.H{"id": orderID})
}

func (h *WorkOrderHandler) Delete(c *gin.Context) {
	log.Printf("WARNING: work_order_handler.Delete is using stub implementation")
	orderID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("invalid order id"))
		return
	}

	response.SuccessWithMessage(c, "work order deleted", gin.H{"id": orderID})
}