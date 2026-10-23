package middleware

import (
	"context"
	"encoding/json"
	"errors"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/stretchr/testify/require"
	"inv-api-server/internal/model"
	"inv-api-server/pkg/response"
)

type runtimeRecorder struct {
	events []model.RuntimeErrorEvent
	err    error
}

func (r *runtimeRecorder) Record(_ context.Context, e model.RuntimeErrorEvent) error {
	r.events = append(r.events, e)
	return r.err
}

func TestRuntimeMonitorCapturesFailuresWithoutSecrets(t *testing.T) {
	for _, mode := range []string{"http", "business", "panic", "panic_after_write", "ok", "denied"} {
		t.Run(mode, func(t *testing.T) {
			recorder := &runtimeRecorder{err: errors.New("store unavailable")}
			r := gin.New()
			r.Use(RuntimeMonitor(recorder))
			r.Use(gin.CustomRecovery(func(c *gin.Context, _ interface{}) { c.Set("runtime_panic", true); c.AbortWithStatus(500) }))
			r.GET("/stations/:id", func(c *gin.Context) {
				switch mode {
				case "http":
					response.InternalError(c, "get station power failed", &pgconn.PgError{Code: "42703", Message: "column l.ac_input_power does not exist", Detail: "password=private"})
				case "business":
					response.Error(c, 500, "private backend detail")
				case "panic":
					panic("private panic detail")
				case "panic_after_write":
					c.JSON(200, gin.H{"code": 0})
					panic("private panic detail")
				case "denied":
					c.Status(403)
				default:
					response.Success(c, nil)
				}
			})
			w := httptest.NewRecorder()
			req := httptest.NewRequest("GET", "/stations/private-device?token=private", nil)
			req.Header.Set("Authorization", "Bearer private")
			req.Header.Set("X-Request-ID", "private-forged")
			r.ServeHTTP(w, req)
			if mode == "ok" || mode == "denied" {
				require.Empty(t, recorder.events)
				return
			}
			require.Len(t, recorder.events, 1)
			e := recorder.events[0]
			require.Equal(t, "/stations/:id", e.Route)
			require.NotEmpty(t, e.RequestID)
			require.Equal(t, w.Header().Get("X-Request-ID"), e.RequestID)
			b, err := json.Marshal(e)
			require.NoError(t, err)
			require.NotContains(t, string(b), "private")
			if mode == "http" {
				require.Equal(t, 500, w.Code)
				require.Equal(t, "missing_column", e.Kind)
				require.Equal(t, "42703", e.SQLState)
				require.Contains(t, e.Summary, "ac_input_power")
				require.NotContains(t, w.Body.String(), "ac_input_power")
			}
			if mode == "business" {
				require.Equal(t, 200, w.Code)
				require.Equal(t, 500, e.Status)
			}
			if mode == "panic" {
				require.Equal(t, "panic", e.Kind)
			}
			if mode == "panic_after_write" {
				require.Equal(t, "panic", e.Kind)
				require.Equal(t, 500, e.Status)
				require.Equal(t, 200, e.HTTPStatus)
			}
		})
	}
}

func TestRuntimeErrorClassificationOmitsSQLData(t *testing.T) {
	for _, err := range []error{
		&pgconn.PgError{Code: "23505", Message: "secret duplicate value", Detail: "secret"},
		&pgconn.PgError{Code: "42703", Message: `column "secret password=123" does not exist`},
		errors.New("secret user data"),
	} {
		_, _, summary := classifyRuntimeError(err)
		require.False(t, strings.Contains(summary, "secret"))
	}
}
