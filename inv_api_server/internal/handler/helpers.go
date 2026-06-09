package handler

import (
	"strconv"

	"github.com/gin-gonic/gin"
)

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
