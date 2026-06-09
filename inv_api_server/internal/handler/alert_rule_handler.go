package handler

import (
	"strconv"

	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

type AlertRuleHandler struct{}

func NewAlertRuleHandler() *AlertRuleHandler {
	return &AlertRuleHandler{}
}

func (h *AlertRuleHandler) List(c *gin.Context) {
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

func (h *AlertRuleHandler) GetByID(c *gin.Context) {
	ruleID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, "invalid rule id")
		return
	}

	response.Success(c, gin.H{
		"id":          ruleID,
		"name":        "示例规则",
		"description": "规则描述",
		"enabled":     true,
		"level":       1,
		"conditions":  []interface{}{},
	})
}

func (h *AlertRuleHandler) Create(c *gin.Context) {
	var req struct {
		Name        string                 `json:"name" binding:"required"`
		Description string                 `json:"description"`
		Enabled     bool                   `json:"enabled"`
		Level       int                    `json:"level"`
		Conditions  []map[string]interface{} `json:"conditions"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	response.SuccessWithMessage(c, "rule created", gin.H{"id": 1})
}

func (h *AlertRuleHandler) Update(c *gin.Context) {
	ruleID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, "invalid rule id")
		return
	}

	var req struct {
		Name        string                 `json:"name"`
		Description string                 `json:"description"`
		Enabled     bool                   `json:"enabled"`
		Level       int                    `json:"level"`
		Conditions  []map[string]interface{} `json:"conditions"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	response.SuccessWithMessage(c, "rule updated", gin.H{"id": ruleID})
}

func (h *AlertRuleHandler) Delete(c *gin.Context) {
	ruleID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, "invalid rule id")
		return
	}

	response.SuccessWithMessage(c, "rule deleted", gin.H{"id": ruleID})
}