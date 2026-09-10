package handler

import (
	"bytes"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// 与 service/esp_image.go 的镜像布局保持一致：应用描述符位于 0x20，
// 其中版本号字段从镜像偏移 0x30 开始、长 32 字节。
const (
	testESPHeaderSize  = 0x50
	testESPVersionOff  = 0x30
	testESPVersionSize = 32
)

func buildESPImage(t *testing.T, version string) []byte {
	t.Helper()
	img := make([]byte, testESPHeaderSize)
	img[0] = 0xe9
	copy(img[0x20:0x24], []byte{0x32, 0x54, 0xcd, 0xab})
	copy(img[testESPVersionOff:testESPVersionOff+testESPVersionSize], []byte(version))
	return img
}

func writeAndOpen(t *testing.T, dir, name string, content []byte) *os.File {
	t.Helper()
	path := filepath.Join(dir, name)
	require.NoError(t, os.WriteFile(path, content, 0o600))
	f, err := os.Open(path)
	require.NoError(t, err)
	t.Cleanup(func() { _ = f.Close() })
	return f
}

func multipartRequest(t *testing.T, path string, fields map[string]string, fileName string, content []byte) *http.Request {
	t.Helper()
	var body bytes.Buffer
	mw := multipart.NewWriter(&body)
	for k, v := range fields {
		require.NoError(t, mw.WriteField(k, v))
	}
	if fileName != "" {
		fw, err := mw.CreateFormFile("file", fileName)
		require.NoError(t, err)
		_, err = fw.Write(content)
		require.NoError(t, err)
	}
	require.NoError(t, mw.Close())

	req := httptest.NewRequest(http.MethodPost, path, &body)
	req.Header.Set("Content-Type", mw.FormDataContentType())
	return req
}

func decodeCodeAndMessage(t *testing.T, w *httptest.ResponseRecorder) (int, string) {
	t.Helper()
	var payload struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &payload))
	return payload.Code, payload.Message
}

// newUploadTestContext 将固件目录指向临时目录，避免测试写入容器真实路径。
func newUploadTestContext(t *testing.T, req *http.Request) (*gin.Context, *httptest.ResponseRecorder) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	t.Setenv("FIRMWARE_DATA_DIR", t.TempDir())
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = req
	return c, w
}

func stagingEntries(t *testing.T, dir string) []string {
	t.Helper()
	entries, err := os.ReadDir(filepath.Join(dir, stagingDirName))
	if os.IsNotExist(err) {
		return nil
	}
	require.NoError(t, err)
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		names = append(names, e.Name())
	}
	return names
}

// ===================== 文件名收敛 =====================

func TestSanitizeFileNamePart(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want string
	}{
		{"包名保留点号", "com.csergy.app1", "com.csergy.app1"},
		{"版本号连字符保留", "1.0.9-beta", "1.0.9-beta"},
		{"空格与特殊字符替换", "my app/v2", "my_app_v2"},
		{"中文替换", "逆变器", "unknown"},
		{"首尾危险字符裁剪", "..__apk..", "apk"},
		{"空串兜底", "///", "unknown"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			assert.Equal(t, tc.want, sanitizeFileNamePart(tc.in))
		})
	}
}

// ===================== 版本号识别 =====================

func TestDetectFirmwareVersion_ESP以镜像内嵌版本为准(t *testing.T) {
	f := writeAndOpen(t, t.TempDir(), "CSL10_6K2_esp_9.9.9.bin", buildESPImage(t, "1.5.1"))

	// 文件名写着 9.9.9，但镜像内嵌 1.5.1：ESP 以本体为准。
	assert.Equal(t, "1.5.1", detectFirmwareVersion(f, "esp", "CSL10_6K2_esp_9.9.9.bin"))
}

func TestDetectFirmwareVersion_ESP大小写不敏感(t *testing.T) {
	f := writeAndOpen(t, t.TempDir(), "esp.bin", buildESPImage(t, "2.3.4"))

	assert.Equal(t, "2.3.4", detectFirmwareVersion(f, "ESP", "esp.bin"))
}

func TestDetectFirmwareVersion_非ESP回退文件名(t *testing.T) {
	f := writeAndOpen(t, t.TempDir(), "CSL10_6K2_arm_1.2.3.bin", []byte("arm-image"))

	assert.Equal(t, "1.2.3", detectFirmwareVersion(f, "arm", "CSL10_6K2_arm_1.2.3.bin"))
}

func TestDetectFirmwareVersion_ESP镜像损坏时回退文件名(t *testing.T) {
	f := writeAndOpen(t, t.TempDir(), "esp_fw_2.0.0.bin", []byte("not-an-esp-image"))

	assert.Equal(t, "2.0.0", detectFirmwareVersion(f, "esp", "esp_fw_2.0.0.bin"))
}

func TestDetectFirmwareVersion_无法识别时返回空(t *testing.T) {
	f := writeAndOpen(t, t.TempDir(), "firmware.bin", []byte("binary"))

	assert.Empty(t, detectFirmwareVersion(f, "arm", "firmware.bin"))
}

// ===================== 上传入口行为 =====================

// 版本号既没有内嵌也不能从文件名识别时，必须在落库前拒绝，且不留下暂存文件。
func TestCreateFirmware_无法识别版本号时拒绝且不留残file(t *testing.T) {
	req := multipartRequest(t, "/api/v1/ota/firmware",
		map[string]string{"model": "CS-INV-6K2", "target_chip": "arm", "version": ""},
		"firmware.bin", []byte("arm-image"))
	c, w := newUploadTestContext(t, req)
	// otaService 为 nil：若守卫未提前返回，会在此处 panic，用例即失败。
	h := &OTAHandler{}

	h.CreateFirmware(c)

	code, msg := decodeCodeAndMessage(t, w)
	assert.Equal(t, 400, code)
	assert.Contains(t, msg, "版本号")

	// 校验失败必须清理暂存文件，且不产生固件目录残留。
	root := os.Getenv("FIRMWARE_DATA_DIR")
	assert.Empty(t, stagingEntries(t, root), "暂存目录应被清理")
	entries, err := os.ReadDir(root)
	require.NoError(t, err)
	for _, e := range entries {
		assert.Equal(t, stagingDirName, e.Name(), "失败的上传不应落盘任何固件文件")
	}
}

// ESP 镜像内嵌版本与操作员填写版本不一致时必须拒绝（防止把固件挂到错误的版本号上）。
func TestCreateFirmware_ESP内嵌版本与填写版本不一致时拒绝(t *testing.T) {
	req := multipartRequest(t, "/api/v1/ota/firmware",
		map[string]string{"model": "CS-INV-6K2", "target_chip": "esp", "version": "9.9.9"},
		"esp.bin", buildESPImage(t, "1.5.1"))
	c, w := newUploadTestContext(t, req)
	h := &OTAHandler{}

	h.CreateFirmware(c)

	code, msg := decodeCodeAndMessage(t, w)
	assert.Equal(t, 400, code)
	assert.Contains(t, msg, "1.5.1")
	assert.Empty(t, stagingEntries(t, os.Getenv("FIRMWARE_DATA_DIR")))
}

// 非 Android 平台直接拒绝，不应进入文件解析流程。
func TestCreateAppVersion_仅接受Android安装包(t *testing.T) {
	req := multipartRequest(t, "/api/v1/ota/app/versions",
		map[string]string{"platform": "ios"}, "", nil)
	c, w := newUploadTestContext(t, req)
	h := &OTAHandler{}

	h.CreateAppVersion(c)

	code, msg := decodeCodeAndMessage(t, w)
	assert.Equal(t, 400, code)
	assert.Contains(t, msg, "Android")
}

// 上传内容不是 APK 时必须报「解析失败」，而不是创建出一条元数据错误的版本记录。
func TestCreateAppVersion_非APK文件解析失败(t *testing.T) {
	req := multipartRequest(t, "/api/v1/ota/app/versions",
		map[string]string{"platform": "android"}, "app.apk", []byte("this is not a zip"))
	c, w := newUploadTestContext(t, req)
	h := &OTAHandler{}

	h.CreateAppVersion(c)

	code, msg := decodeCodeAndMessage(t, w)
	assert.Equal(t, 400, code)
	assert.Contains(t, msg, "解析失败")
	assert.Empty(t, stagingEntries(t, os.Getenv("FIRMWARE_DATA_DIR")))
}

// 选择安装包但未附带文件时给出明确提示。
func TestCreateAppVersion_缺少文件时提示(t *testing.T) {
	req := multipartRequest(t, "/api/v1/ota/app/versions",
		map[string]string{"platform": "android"}, "", nil)
	c, w := newUploadTestContext(t, req)
	h := &OTAHandler{}

	h.CreateAppVersion(c)

	code, msg := decodeCodeAndMessage(t, w)
	assert.Equal(t, 400, code)
	assert.Contains(t, msg, "安装包")
}
