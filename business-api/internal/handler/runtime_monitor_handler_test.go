package handler

import (
	"inv-api-server/internal/repository"
	"inv-api-server/internal/service"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestRuntimeMonitorRequiresSystemAdmin(t *testing.T) {
	for _, admin := range []bool{false, true} {
		r := gin.New()
		r.Use(func(c *gin.Context) { c.Set("is_system_admin", admin) })
		svc := service.NewRuntimeMonitorService(repository.NewRuntimeMonitorRepository(nil, nil))
		r.GET("/admin/runtime-monitor", RuntimeMonitorHandler(svc))
		w := httptest.NewRecorder()
		r.ServeHTTP(w, httptest.NewRequest("GET", "/admin/runtime-monitor", nil))
		if admin {
			require.Equal(t, 200, w.Code)
			require.Contains(t, w.Body.String(), `"errors_status":"unknown"`)
			require.Contains(t, w.Body.String(), `"errors_5m":null`)
		} else {
			require.Equal(t, 403, w.Code)
			require.NotContains(t, w.Body.String(), "checks")
		}
	}
}
