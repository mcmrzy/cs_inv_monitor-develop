package handler

import (
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestLocalResultAcceptsExistingAppReadbackContract(t *testing.T) {
	for _, tc := range []struct {
		body string
		want bool
	}{
		{`{"target_chip":"dsp","new_version":"1.0.50","firmware_id":101}`, true},
		{`{"status":"success","target_chip":"dsp","new_version":"1.0.50","firmware_id":101}`, true},
		{`{"status":"failed","target_chip":"dsp","new_version":"1.0.50","firmware_id":101}`, false},
		{`{"target_chip":"dsp","firmware_id":101}`, false},
		{`{"status":"pending","target_chip":"dsp","new_version":"1.0.50","firmware_id":101}`, false},
	} {
		c, _ := gin.CreateTestContext(httptest.NewRecorder())
		c.Request = httptest.NewRequest("POST", "/local-ota-result", strings.NewReader(tc.body))
		c.Request.Header.Set("Content-Type", "application/json")
		var req localOTAResultRequest
		require.NoError(t, c.ShouldBindJSON(&req))
		require.Equal(t, tc.want, req.succeeded(), tc.body)
	}
}
