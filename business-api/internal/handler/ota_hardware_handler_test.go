package handler

import (
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHardwareRangeAdministrationRequiresSystemAdmin(t *testing.T) {
	for _, run := range []func(*OTAHandler, *gin.Context){(*OTAHandler).CreateHardwareVersion, (*OTAHandler).UpdateFirmwareHardwareVersions} {
		w := httptest.NewRecorder()
		c, _ := gin.CreateTestContext(w)
		c.Request = httptest.NewRequest("POST", "/ota/hardware-versions", strings.NewReader(`{"model":"L10","version":"HW-1"}`))
		run(&OTAHandler{}, c)
		code, _ := decodeCodeAndMessage(t, w)
		require.Equal(t, 403, code)
	}
}

func TestFirmwareUploadWithoutHardwareRangeStillValidatesTarget(t *testing.T) {
	req := multipartRequest(t, "/api/v1/ota/firmware", map[string]string{"model": "L10", "target_chip": "invalid"}, "arm_1.0.0.bin", []byte("arm-image"))
	c, w := newUploadTestContext(t, req)
	(&OTAHandler{}).CreateFirmware(c)
	code, message := decodeCodeAndMessage(t, w)
	require.Equal(t, 400, code)
	require.Contains(t, message, "芯片")
	require.NotContains(t, message, "板卡")
}

func TestFirmwareJSONWithoutHardwareRangeStillValidatesIntegrity(t *testing.T) {
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest("POST", "/ota/firmware", strings.NewReader(`{"model":"L10","target_chip":"dsp","version":"1.0.50","file_url":"/firmware/dsp.bin","file_size":100}`))
	c.Request.Header.Set("Content-Type", "application/json")
	(&OTAHandler{}).CreateFirmware(c)
	code, message := decodeCodeAndMessage(t, w)
	require.Equal(t, 400, code)
	require.Contains(t, message, "SHA-256")
}

func TestFirmwareUploadHardwareFormParsing(t *testing.T) {
	versions, err := parseHardwareVersionsForm(`[" hw-2 ","HW-1","HW-2"]`)
	require.NoError(t, err)
	require.Equal(t, []string{"HW-1", "HW-2"}, versions)
	versions, err = parseHardwareVersionsForm(`[]`)
	require.NoError(t, err)
	require.Empty(t, versions)
	for _, raw := range []string{"", `[""]`, `["*"]`, `"HW-1"`, `["HW-1",3]`} {
		_, err := parseHardwareVersionsForm(raw)
		require.Error(t, err)
	}
}

func TestFirmwareBoardCodesKeepExactModuleIdentity(t *testing.T) {
	codes, err := parseBoardCodesForm(`["COMM-A","COMM-B.2"]`)
	require.NoError(t, err)
	require.Equal(t, []string{"COMM-A", "COMM-B.2"}, codes)
	codes, err = parseBoardCodesForm(`[]`)
	require.NoError(t, err)
	require.Empty(t, codes)
	for _, raw := range []string{`["comm-a"]`, `[" COMM-A "]`, `["COMM-A","COMM-A"]`, `["*"]`, `"COMM-A"`} {
		_, err = parseBoardCodesForm(raw)
		require.Error(t, err, raw)
	}
}

// The candidate listing must reject a malformed id before touching scope or DB.
func TestTaskCandidatesRejectInvalidFirmwareID(t *testing.T) {
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest("GET", "/api/v1/ota/firmware/0/task-candidates", nil)
	c.Params = gin.Params{{Key: "id", Value: "0"}}
	(&OTAHandler{}).ListFirmwareTaskCandidates(c)
	code, _ := decodeCodeAndMessage(t, w)
	require.Equal(t, 400, code)
}
