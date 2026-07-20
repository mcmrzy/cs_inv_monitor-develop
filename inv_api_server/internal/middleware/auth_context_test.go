package middleware

import (
	"testing"

	"github.com/gin-gonic/gin"
)

func TestGetRoleFailsClosed(t *testing.T) {
	c, _ := gin.CreateTestContext(nil)
	if got := GetRole(c); got != -1 {
		t.Fatalf("missing role must not default to super administrator: got %d", got)
	}
	c.Set("role", "0")
	if got := GetRole(c); got != -1 {
		t.Fatalf("invalid role type must not default to super administrator: got %d", got)
	}
	c.Set("role", 0)
	if got := GetRole(c); got != 0 {
		t.Fatalf("valid super administrator role = %d", got)
	}
}
