package middleware

import (
	"testing"

	"github.com/gin-gonic/gin"
)

func TestGetIsSystemAdminFailsClosed(t *testing.T) {
	c, _ := gin.CreateTestContext(nil)
	if got := GetIsSystemAdmin(c); got {
		t.Fatalf("missing is_system_admin must not default to true")
	}
	c.Set("is_system_admin", "true")
	if got := GetIsSystemAdmin(c); got {
		t.Fatalf("invalid is_system_admin type must not default to true")
	}
	c.Set("is_system_admin", true)
	if got := GetIsSystemAdmin(c); !got {
		t.Fatalf("valid is_system_admin=true must return true")
	}
}
