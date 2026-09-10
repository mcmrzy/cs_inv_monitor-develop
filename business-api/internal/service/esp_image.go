package service

import (
	"bytes"
	"fmt"
	"io"
	"strings"
)

const (
	espImageHeaderSize = 0x50
	espVersionOffset   = 0x30
	espVersionSize     = 32
)

var espAppDescriptorMagic = []byte{0x32, 0x54, 0xcd, 0xab}

// ReadESPImageVersion 读取 ESP-IDF 应用镜像内嵌的工程版本号。
// 上传固件时以镜像本体为版本号权威来源，无需操作员手工填写。
func ReadESPImageVersion(r io.ReaderAt) (string, error) {
	header := make([]byte, espImageHeaderSize)
	if _, err := r.ReadAt(header, 0); err != nil {
		return "", fmt.Errorf("读取 ESP-IDF 固件头失败: %w", err)
	}
	if header[0] != 0xe9 || !bytes.Equal(header[0x20:0x24], espAppDescriptorMagic) {
		return "", fmt.Errorf("不是有效的 ESP-IDF 应用镜像")
	}

	versionBytes := header[espVersionOffset : espVersionOffset+espVersionSize]
	if end := bytes.IndexByte(versionBytes, 0); end >= 0 {
		versionBytes = versionBytes[:end]
	}
	embeddedVersion := strings.TrimSpace(string(versionBytes))
	if embeddedVersion == "" {
		return "", fmt.Errorf("ESP-IDF 固件未包含版本号")
	}
	return embeddedVersion, nil
}

// ValidateESPImageVersion verifies that an uploaded ESP-IDF application image
// carries the same project version as the version declared by the operator.
func ValidateESPImageVersion(r io.ReaderAt, declaredVersion string) error {
	embeddedVersion, err := ReadESPImageVersion(r)
	if err != nil {
		return err
	}
	declaredVersion = strings.TrimSpace(declaredVersion)
	if embeddedVersion != declaredVersion {
		return fmt.Errorf("固件内嵌版本 %s 与填写版本 %s 不一致", embeddedVersion, declaredVersion)
	}
	return nil
}
