package service

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"

	"inv-device-server/internal/mqtt"

	"github.com/stretchr/testify/assert"
)

func TestDataService_HandleCmdResult_SNInjection(t *testing.T) {
	var received map[string]interface{}
	handler := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "/api/v1/internal/device-cmd-result", r.URL.Path)
		assert.Equal(t, "application/json", r.Header.Get("Content-Type"))
		assert.Equal(t, "test-key", r.Header.Get("X-Internal-Key"))

		body, _ := io.ReadAll(r.Body)
		defer r.Body.Close()
		err := json.Unmarshal(body, &received)
		assert.NoError(t, err)

		w.WriteHeader(http.StatusOK)
	}))
	defer handler.Close()

	service := NewDataService(nil, nil, mqtt.NewHub(nil), nil, handler.URL, "test-key")

	// payload 不包含 sn，应由 HandleCmdResult 注入
	payload := []byte(`{"task_id":"task_1","result":"success"}`)
	service.HandleCmdResult("SN001", payload)

	assert.NotNil(t, received)
	assert.Equal(t, "SN001", received["sn"])
	assert.Equal(t, "task_1", received["task_id"])
	assert.Equal(t, "success", received["result"])
}

func TestDataService_HandleCmdResult_AlreadyHasSN(t *testing.T) {
	var received map[string]interface{}
	handler := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		defer r.Body.Close()
		_ = json.Unmarshal(body, &received)
		w.WriteHeader(http.StatusOK)
	}))
	defer handler.Close()

	service := NewDataService(nil, nil, mqtt.NewHub(nil), nil, handler.URL, "test-key")

	payload := []byte(`{"sn":"SN002","task_id":"task_1","result":"success"}`)
	service.HandleCmdResult("SN001", payload)

	assert.Equal(t, "SN002", received["sn"])
}

func TestDataService_HandleCmdResult_EmptyAPIServer(t *testing.T) {
	service := NewDataService(nil, nil, mqtt.NewHub(nil), nil, "", "")
	// 不应 panic，也不应发送请求
	service.HandleCmdResult("SN001", []byte(`{"task_id":"task_1"}`))
}

func TestDataService_HandleOTACmdAck(t *testing.T) {
	var received map[string]interface{}
	handler := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "/api/v1/internal/ota-cmd-ack", r.URL.Path)
		body, _ := io.ReadAll(r.Body)
		defer r.Body.Close()
		_ = json.Unmarshal(body, &received)
		w.WriteHeader(http.StatusOK)
	}))
	defer handler.Close()

	service := NewDataService(nil, nil, mqtt.NewHub(nil), nil, handler.URL, "test-key")

	payload := []byte(`{"ack":true,"task_id":"ota_1","message":"开始升级","timestamp":1700000000}`)
	service.HandleOTACmdAck("SN001", payload)

	assert.Equal(t, "SN001", received["device_sn"])
	assert.Equal(t, true, received["ack"])
	assert.Equal(t, "ota_1", received["task_id"])
}

func TestDataService_HandleOTACmdAck_InvalidJSON(t *testing.T) {
	service := NewDataService(nil, nil, mqtt.NewHub(nil), nil, "http://api", "key")
	// 不应 panic
	service.HandleOTACmdAck("SN001", []byte("not json"))
}

func TestDataService_HandleOTAStatus_Nested(t *testing.T) {
	var received map[string]interface{}
	handler := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "/api/v1/internal/ota-status", r.URL.Path)
		body, _ := io.ReadAll(r.Body)
		defer r.Body.Close()
		_ = json.Unmarshal(body, &received)
		w.WriteHeader(http.StatusOK)
	}))
	defer handler.Close()

	service := NewDataService(nil, nil, mqtt.NewHub(nil), nil, handler.URL, "test-key")

	// 嵌套格式
	payload := []byte(`{"data":{"device_id":"SN001","state":"upgrading","progress":45,"status_message":"升级中"},"timestamp":1700000000}`)
	service.HandleOTAStatus("SN001", payload)

	assert.Equal(t, "SN001", received["device_sn"])
	assert.Equal(t, "upgrading", received["status"])
	assert.Equal(t, float64(45), received["progress"])
	assert.Equal(t, "升级中", received["message"])
}

func TestDataService_HandleOTAStatus_Flat(t *testing.T) {
	var received map[string]interface{}
	handler := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		defer r.Body.Close()
		_ = json.Unmarshal(body, &received)
		w.WriteHeader(http.StatusOK)
	}))
	defer handler.Close()

	service := NewDataService(nil, nil, mqtt.NewHub(nil), nil, handler.URL, "test-key")

	payload := []byte(`{"state":"completed","progress":100,"message":"升级完成"}`)
	service.HandleOTAStatus("SN001", payload)

	assert.Equal(t, "completed", received["status"])
	assert.Equal(t, float64(100), received["progress"])
	assert.Equal(t, "升级完成", received["message"])
}

func TestDataService_HandleOTAStatus_ACK(t *testing.T) {
	called := false
	handler := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusOK)
	}))
	defer handler.Close()

	service := NewDataService(nil, nil, mqtt.NewHub(nil), nil, handler.URL, "test-key")

	// ACK 消息不应转发
	payload := []byte(`{"ack":true,"task_id":"ota_1"}`)
	service.HandleOTAStatus("SN001", payload)

	assert.False(t, called)
}

func TestDataService_HandleOTAStatus_Failed(t *testing.T) {
	var received map[string]interface{}
	handler := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		defer r.Body.Close()
		_ = json.Unmarshal(body, &received)
		w.WriteHeader(http.StatusOK)
	}))
	defer handler.Close()

	service := NewDataService(nil, nil, mqtt.NewHub(nil), nil, handler.URL, "test-key")

	payload := []byte(`{"state":"failed","progress":30,"error_message":"校验失败"}`)
	service.HandleOTAStatus("SN001", payload)

	assert.Equal(t, "failed", received["status"])
	assert.Equal(t, float64(1), received["err_code"])
}

func TestDataService_HandleOTAStatus_FirmwareID(t *testing.T) {
	var received map[string]interface{}
	handler := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		defer r.Body.Close()
		_ = json.Unmarshal(body, &received)
		w.WriteHeader(http.StatusOK)
	}))
	defer handler.Close()

	service := NewDataService(nil, nil, mqtt.NewHub(nil), nil, handler.URL, "test-key")

	payload := []byte(`{"state":"upgrading","progress":10,"firmware_id":42}`)
	service.HandleOTAStatus("SN001", payload)

	assert.Equal(t, float64(42), received["firmware_id"])
}

func TestDataService_SendCommand(t *testing.T) {
	hub := mqtt.NewHub(nil)
	service := NewDataService(nil, nil, hub, nil, "", "")

	err := service.SendCommand("SN001", "set_control", map[string]interface{}{"power": 100}, nil)
	assert.NoError(t, err)

	select {
	case cmd := <-hub.GetCmdChan():
		assert.Equal(t, "SN001", cmd.DeviceSN)
		assert.Equal(t, "set_control", cmd.CmdType)
	default:
		t.Fatal("expected command in channel")
	}
}

func TestDataService_IsDeviceOnline(t *testing.T) {
	hub := mqtt.NewHub(nil)
	service := NewDataService(nil, nil, hub, nil, "", "")

	assert.False(t, service.IsDeviceOnline("SN001"))
}

func TestDataService_GetMQTTStats(t *testing.T) {
	hub := mqtt.NewHub(nil)
	service := NewDataService(nil, nil, hub, nil, "", "")

	stats := service.GetMQTTStats()
	assert.Equal(t, int64(0), stats.DataReceived)
}

func TestDataService_GetOnlineDeviceSNs(t *testing.T) {
	hub := mqtt.NewHub(nil)
	service := NewDataService(nil, nil, hub, nil, "", "")

	sns := service.GetOnlineDeviceSNs()
	assert.Empty(t, sns)
}

func TestDataService_FlushPendingCommands_NoRedis(t *testing.T) {
	service := NewDataService(nil, nil, mqtt.NewHub(nil), nil, "", "")
	// nil redis 应直接返回，不 panic
	service.FlushPendingCommands(t.Context(), "SN001")
}

func TestDataService_IsOnlineViaRedis_NoRedis(t *testing.T) {
	service := NewDataService(nil, nil, mqtt.NewHub(nil), nil, "", "")
	assert.False(t, service.IsOnlineViaRedis(t.Context(), "SN001"))
}

func TestDataService_GetOnlineSNsFromRedis_NoRedis(t *testing.T) {
	service := NewDataService(nil, nil, mqtt.NewHub(nil), nil, "", "")
	assert.Nil(t, service.GetOnlineSNsFromRedis(t.Context()))
}

func TestDataService_ConcurrentSendCommand(t *testing.T) {
	hub := mqtt.NewHub(nil)
	service := NewDataService(nil, nil, hub, nil, "", "")

	var wg sync.WaitGroup
	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			_ = service.SendCommand("SN001", "set_control", map[string]interface{}{"idx": idx}, nil)
		}(i)
	}
	wg.Wait()

	count := 0
	for {
		select {
		case <-hub.GetCmdChan():
			count++
		default:
			assert.Equal(t, 50, count)
			return
		}
	}
}
