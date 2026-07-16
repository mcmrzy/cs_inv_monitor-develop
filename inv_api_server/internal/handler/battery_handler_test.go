package handler

import (
	"context"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

func TestBatteryAuthorizeDevice_AdminAllowed(t *testing.T) {
	ctx, _ := newEnergyScheduleAuthContext(0, 1)
	handler := &BatteryHandler{}

	assert.True(t, handler.authorizeDevice(ctx, "TEST"))
}

func TestBatteryAuthorizeDevice_OwnerAllowed(t *testing.T) {
	ctx, _ := newEnergyScheduleAuthContext(1, 42)
	handler := &BatteryHandler{
		hasPermission: func(_ context.Context, userID int64, sn string) bool {
			return userID == 42 && sn == "TEST"
		},
	}

	assert.True(t, handler.authorizeDevice(ctx, "TEST"))
}

func TestBatteryAuthorizeDevice_NonOwnerForbidden(t *testing.T) {
	recorder := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(recorder)
	ctx.Request = httptest.NewRequest("GET", "/devices/OTHER/battery-config", nil)
	ctx.Set("role", 1)
	ctx.Set("user_id", int64(42))
	handler := &BatteryHandler{
		hasPermission: func(context.Context, int64, string) bool { return false },
	}

	assert.False(t, handler.authorizeDevice(ctx, "OTHER"))
	assert.Equal(t, 403, recorder.Code)
}
