package service

import "testing"

func TestCompareModuleVersionFieldFormats(t *testing.T) {
	cases := []struct {
		a, b string
		want int
	}{
		// 设备上报 V主.次 与目录三段版本
		{"V1.5", "1.5.2", -1},
		{"V1.5", "V1.5.2", -1},
		{"1.5.10", "1.6.0", -1},
		{"V1.5.10", "1.6.0", -1},
		{"1.5", "1.5.2", -1},
		// 尾零等价，不得误报可升级
		{"1.5.0", "1.5", 0},
		{"V1.5.0", "1.5", 0},
		{"1.6.0", "1.6", 0},
		// 反向：设备已超前目录
		{"1.6.1", "1.6.0", 1},
	}
	for _, c := range cases {
		if got := CompareModuleVersion(c.a, c.b); got != c.want {
			t.Errorf("CompareModuleVersion(%q, %q) = %d, want %d", c.a, c.b, got, c.want)
		}
	}
}

func TestVersionStateFieldFormats(t *testing.T) {
	state, upd := VersionState("V1.5", "1.5.2")
	if state != "outdated" || !upd {
		t.Fatalf("V1.5 vs 1.5.2 => %s/%v, want outdated/true", state, upd)
	}
	state, upd = VersionState("1.5.10", "1.6.0")
	if state != "outdated" || !upd {
		t.Fatalf("1.5.10 vs 1.6.0 => %s/%v, want outdated/true", state, upd)
	}
	state, upd = VersionState("1.5.0", "1.5")
	if state != "current" || upd {
		t.Fatalf("1.5.0 vs 1.5 => %s/%v, want current/false", state, upd)
	}
}
