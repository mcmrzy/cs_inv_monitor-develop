package handler

import (
	"github.com/gin-gonic/gin"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHardwareWritesRequireSystemAdministrator(t *testing.T) {
	gin.SetMode(gin.TestMode)
	h := NewHardwareRegistryHandler(nil, nil)
	for _, fn := range []gin.HandlerFunc{h.CreateBoardType, h.Verify, h.Correct, h.ServiceChange, h.Freeze, h.StageImport, h.CommitImport, h.SetFirmwareBoards, h.CreateCompatibilityWindow} {
		w := httptest.NewRecorder()
		ctx, _ := gin.CreateTestContext(w)
		ctx.Request = httptest.NewRequest(http.MethodPost, "/", nil)
		ctx.Set("user_id", int64(4))
		ctx.Set("is_system_admin", false)
		fn(ctx)
		if w.Code != http.StatusForbidden {
			t.Fatalf("write not denied: %d %s", w.Code, w.Body.String())
		}
	}
}
