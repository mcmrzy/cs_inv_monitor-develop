package service

import (
	"bytes"
	"strings"
	"testing"
)

func makeESPImage(version string) []byte {
	image := make([]byte, 0x50)
	image[0] = 0xe9
	copy(image[0x20:0x24], []byte{0x32, 0x54, 0xcd, 0xab})
	copy(image[0x30:0x50], version)
	return image
}

func TestValidateESPImageVersion(t *testing.T) {
	tests := []struct {
		name     string
		image    []byte
		declared string
		wantErr  string
	}{
		{name: "matching version", image: makeESPImage("1.5.0"), declared: "1.5.0"},
		{name: "mismatched version", image: makeESPImage("1.4.3"), declared: "1.5.0", wantErr: "固件内嵌版本 1.4.3 与填写版本 1.5.0 不一致"},
		{name: "invalid image magic", image: make([]byte, 0x50), declared: "1.5.0", wantErr: "不是有效的 ESP-IDF 应用镜像"},
		{name: "truncated image", image: make([]byte, 20), declared: "1.5.0", wantErr: "读取 ESP-IDF 固件头失败"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidateESPImageVersion(bytes.NewReader(tt.image), tt.declared)
			if tt.wantErr == "" {
				if err != nil {
					t.Fatalf("ValidateESPImageVersion() error = %v", err)
				}
				return
			}
			if err == nil || !strings.Contains(err.Error(), tt.wantErr) {
				t.Fatalf("ValidateESPImageVersion() error = %v, want containing %q", err, tt.wantErr)
			}
		})
	}
}
