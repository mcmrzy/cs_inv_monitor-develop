package handler

import (
	"encoding/json"
	"net/http"
	"testing"

	"inv-api-server/internal/model"

	"github.com/stretchr/testify/require"
)

func TestLegacyPackageRetiredReturnsHTTPGoneWithStableCode(t *testing.T) {
	c, recorder := createTestGinContext("/api/v1/ota/packages", http.MethodPost, nil)

	(&OTAHandler{}).LegacyPackageRetired(c)

	require.Equal(t, http.StatusGone, recorder.Code)
	var body struct {
		Code    string `json:"code"`
		Message string `json:"message"`
	}
	require.NoError(t, json.Unmarshal(recorder.Body.Bytes(), &body))
	require.Equal(t, model.ErrCodeLegacyPackageRetired, body.Code)
	require.NotEmpty(t, body.Message)
}
