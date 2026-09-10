package apkmeta

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// 仓库内发布目录保留了真实 Android 安装包（本地构建产物，不入版本库）。
// 只要该文件存在，本用例就在真实 AGP 产出的二进制 manifest 上验证解析器；
// 文件缺失时自动跳过，因此 CI 与干净检出不受影响。
const repoRootAPK = "../../../deploy/web/apk/app-release.apk"

func TestFromAPK_真实安装包Fixtures(t *testing.T) {
	abs, err := filepath.Abs(repoRootAPK)
	if err != nil {
		t.Fatal(err)
	}
	root, err := filepath.Abs("../../..")
	if err != nil {
		t.Fatal(err)
	}
	rel, err := filepath.Rel(root, abs)
	if err != nil || strings.HasPrefix(rel, "..") {
		t.Fatalf("fixture 路径越出仓库范围: %s", abs)
	}

	f, err := os.Open(abs)
	if err != nil {
		t.Skipf("真实 APK fixture 不可用: %v", err)
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		t.Fatal(err)
	}

	meta, err := FromAPK(f, st.Size())
	if err != nil {
		t.Fatalf("解析真实 APK 失败: %v", err)
	}
	fmt.Printf("真实 APK: package=%q versionName=%q versionCode=%d minSdk=%d targetSdk=%d\n",
		meta.PackageName, meta.VersionName, meta.VersionCode, meta.MinSDK, meta.TargetSDK)

	if meta.PackageName == "" || meta.VersionName == "" || meta.VersionCode <= 0 {
		t.Fatalf("真实 APK 未解析出完整的包名/版本信息: %+v", meta)
	}
	if meta.MinSDK <= 0 {
		t.Fatalf("真实 APK 未解析出 minSdkVersion: %+v", meta)
	}
	if !strings.HasPrefix(meta.PackageName, "com.") {
		t.Fatalf("包名格式异常: %q", meta.PackageName)
	}
}
