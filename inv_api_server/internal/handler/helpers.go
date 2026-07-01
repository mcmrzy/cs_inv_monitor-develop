package handler

import (
	"regexp"
	"strconv"

	"github.com/gin-gonic/gin"
)

// SN 格式正则：大写字母+数字，长度 8-32
var snRegex = regexp.MustCompile(`^[A-Z0-9]{8,32}$`)

func parseID(s string) int64 {
	id, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return 0
	}
	return id
}

func parseInt(s string) int {
	v, err := strconv.Atoi(s)
	if err != nil {
		return 0
	}
	return v
}

func getQueryInt(c *gin.Context, key string, defaultValue int) int {
	s := c.Query(key)
	if s == "" {
		return defaultValue
	}
	v, err := strconv.Atoi(s)
	if err != nil {
		return defaultValue
	}
	return v
}

func getQueryInt64(c *gin.Context, key string, defaultValue int64) int64 {
	s := c.Query(key)
	if s == "" {
		return defaultValue
	}
	v, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return defaultValue
	}
	return v
}

// parsePagination 统一分页参数解析，返回 page 和 pageSize。
// 默认 page=1, pageSize=20，最大 pageSize=100。
func parsePagination(c *gin.Context) (page, pageSize int) {
	page = getQueryInt(c, "page", 1)
	if page < 1 {
		page = 1
	}
	pageSize = getQueryInt(c, "pageSize", 20)
	if pageSize < 1 {
		pageSize = 20
	}
	if pageSize > 100 {
		pageSize = 100
	}
	return
}

// validateSN 校验设备 SN 格式（大写字母+数字，长度 8-32）
func validateSN(sn string) bool {
	return snRegex.MatchString(sn)
}
