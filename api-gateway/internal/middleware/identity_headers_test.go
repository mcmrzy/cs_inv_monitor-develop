package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

func TestSanitizeIdentityHeadersOnPublicRoutes(t *testing.T) {
	router := gin.New()
	router.Use(SanitizeIdentityHeaders())
	router.GET("/public", func(c *gin.Context) {
		c.String(http.StatusOK, c.GetHeader("X-User-ID")+c.GetHeader("X-Token-JTI"))
	})
	req := httptest.NewRequest(http.MethodGet, "/public", nil)
	req.Header.Set("X-User-ID", "1")
	req.Header.Set("X-Token-JTI", "forged")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)
	assert.Empty(t, w.Body.String())
}
