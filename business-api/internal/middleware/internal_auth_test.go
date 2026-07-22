package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

func TestInternalAuth(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name       string
		configured string
		provided   string
		wantStatus int
	}{
		{name: "matching key", configured: "integration-internal-key", provided: "integration-internal-key", wantStatus: http.StatusNoContent},
		{name: "wrong key", configured: "integration-internal-key", provided: "wrong", wantStatus: http.StatusUnauthorized},
		{name: "missing header", configured: "integration-internal-key", wantStatus: http.StatusUnauthorized},
		{name: "empty configuration fails closed", provided: "anything", wantStatus: http.StatusUnauthorized},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			router := gin.New()
			router.GET("/internal", InternalAuth(tt.configured), func(c *gin.Context) {
				c.Status(http.StatusNoContent)
			})

			req := httptest.NewRequest(http.MethodGet, "/internal", nil)
			if tt.provided != "" {
				req.Header.Set("X-Internal-Key", tt.provided)
			}
			recorder := httptest.NewRecorder()
			router.ServeHTTP(recorder, req)

			assert.Equal(t, tt.wantStatus, recorder.Code)
		})
	}
}
