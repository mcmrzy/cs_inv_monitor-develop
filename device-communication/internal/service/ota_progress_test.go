package service

import (
	"encoding/json"
	"github.com/stretchr/testify/require"
	"inv-device-server/internal/mqtt"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestOTAStageProgressForwarding(t *testing.T) {
	for _, nested := range []bool{false, true} {
		var got map[string]interface{}
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			require.NoError(t, json.NewDecoder(r.Body).Decode(&got))
			w.WriteHeader(http.StatusOK)
		}))
		payload := `{"state":"installing","progress":70,"stage":"transferring","stage_progress":0,"overall_progress":70,"target":"dsp"}`
		if nested {
			payload = `{"data":` + payload + `}`
		}
		service := NewDataService(nil, nil, mqtt.NewHub(nil), nil, server.URL, "key")
		service.HandleOTAStatus("SN", []byte(payload))
		server.Close()
		require.Equal(t, "transferring", got["stage"])
		require.Equal(t, float64(0), got["stage_progress"])
		require.Equal(t, float64(70), got["overall_progress"])
		require.Equal(t, float64(70), got["progress"])
	}
}
