package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"inv-device-server/internal/config"
	"inv-device-server/internal/mqtt"
	"inv-device-server/internal/service"
	"inv-device-server/pkg/logger"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/require"
)

func TestOfflineOTADatabaseRecoveryDoesNotQueueStalePayload(t *testing.T) {
	require.NoError(t, logger.Init(&config.LogConfig{Level: "error"}))
	for _, tc := range []struct {
		name   string
		flag   string
		status int
		queued int64
	}{
		{"database recovery", `,"queue_if_offline":false`, http.StatusServiceUnavailable, 0},
		{"legacy queue", "", http.StatusAccepted, 1},
	} {
		t.Run(tc.name, func(t *testing.T) {
			mr := miniredis.RunT(t)
			rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
			defer rdb.Close()
			hub := mqtt.NewHub(rdb)
			ds := service.NewDataService(nil, nil, hub, rdb, "", "")
			router := setupRouter(&config.Config{}, ds, nil, rdb)
			w := httptest.NewRecorder()
			router.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/api/v1/device/SN/command", strings.NewReader(`{"command":"start","upgrade_id":1`+tc.flag+`}`)))
			require.Equal(t, tc.status, w.Code, w.Body.String())
			require.Equal(t, tc.queued, rdb.LLen(t.Context(), "device:cmd:queue:SN").Val())
		})
	}
}
