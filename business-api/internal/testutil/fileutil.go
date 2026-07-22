package testutil

import (
	"io"
	"os"
)

// openFileOS 使用 os.Open 打开文件
func openFileOS(path string) (io.ReadCloser, error) {
	return os.Open(path)
}
