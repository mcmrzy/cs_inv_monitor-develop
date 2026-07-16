package handler

import (
	"context"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

func newEnergyScheduleAuthContext(role int, userID int64) (*gin.Context, *httptest.ResponseRecorder) {
	recorder := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(recorder)
	ctx.Request = httptest.NewRequest("GET", "/devices/TEST/energy-schedule", nil)
	ctx.Set("role", role)
	ctx.Set("user_id", userID)
	return ctx, recorder
}

func TestEnergyScheduleAuthorizeDevice_AdminAllowed(t *testing.T) {
	ctx, _ := newEnergyScheduleAuthContext(0, 1)
	handler := &EnergyScheduleHandler{}

	assert.True(t, handler.authorizeDevice(ctx, "TEST"))
}

func TestEnergyScheduleAuthorizeDevice_OwnerAllowed(t *testing.T) {
	ctx, _ := newEnergyScheduleAuthContext(1, 42)
	handler := &EnergyScheduleHandler{
		hasPermission: func(_ context.Context, userID int64, sn string) bool {
			return userID == 42 && sn == "TEST"
		},
	}

	assert.True(t, handler.authorizeDevice(ctx, "TEST"))
}

func TestEnergyScheduleAuthorizeDevice_NonOwnerForbidden(t *testing.T) {
	ctx, recorder := newEnergyScheduleAuthContext(1, 42)
	handler := &EnergyScheduleHandler{
		hasPermission: func(context.Context, int64, string) bool { return false },
	}

	assert.False(t, handler.authorizeDevice(ctx, "OTHER"))
	assert.Equal(t, 403, recorder.Code)
}

func TestEnergyScheduleAuthorizeDevice_MissingCheckerForbidden(t *testing.T) {
	ctx, recorder := newEnergyScheduleAuthContext(1, 42)
	handler := &EnergyScheduleHandler{}

	assert.False(t, handler.authorizeDevice(ctx, "TEST"))
	assert.Equal(t, 403, recorder.Code)
}
