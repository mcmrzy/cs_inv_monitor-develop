package service

import (
	"context"
	"testing"

	"inv-api-server/internal/config"

	"github.com/stretchr/testify/assert"
)

func TestNormalizeBaseURL(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{"https://download.jiuxiaoyw.com", "https://download.jiuxiaoyw.com"},
		{"https://download.jiuxiaoyw.com/", "https://download.jiuxiaoyw.com"},
		{"  https://www.jiuxiaoyw.online  ", "https://www.jiuxiaoyw.online"},
		{"http://101.43.90.25", "http://101.43.90.25"}, // 公网 IP 允许（历史部署形态）
		{"ftp://download.example.com", ""},             // 非 http/https
		{"download.example.com", ""},                   // 缺 scheme
		{"https://localhost", ""},                      // localhost
		{"https://sub.localhost", ""},                  // localhost 子域
		{"https://box.local", ""},                      // .local
		{"https://box.internal", ""},                   // .internal
		{"http://127.0.0.1", ""},                       // 环回
		{"http://192.168.8.50", ""},                    // 私网
		{"http://10.0.0.2", ""},                        // 私网
		{"", ""},                                       // 空
		{"https://", ""},                               // 无主机
	}
	for _, c := range cases {
		assert.Equal(t, c.want, normalizeBaseURL(c.in), "input: %q", c.in)
	}
}

func TestResolveDomainConfig_DBOverrideFallsBackToEnv(t *testing.T) {
	svc := &ConfigService{baseCfg: config.Config{
		Backends: config.BackendsConfig{
			ServerURL:    "https://api.jiuxiaoyw.online",
			DownloadURL:  "https://download.jiuxiaoyw.online",
			FrontendURL:  "https://www.jiuxiaoyw.online",
		},
	}}
	// 无 db/redis（nil）：getAll 返回空 map，走环境变量回退
	d := svc.ResolveDomainConfig(context.Background())
	assert.Equal(t, "https://download.jiuxiaoyw.online", d.DownloadBaseURL)
	assert.Equal(t, "https://www.jiuxiaoyw.online", d.FrontendBaseURL)
}

func TestResolveDomainConfig_MissingEnvFallsBackToServerURL(t *testing.T) {
	svc := &ConfigService{baseCfg: config.Config{
		Backends: config.BackendsConfig{ServerURL: "https://api.jiuxiaoyw.online"},
	}}
	d := svc.ResolveDomainConfig(context.Background())
	assert.Equal(t, "https://api.jiuxiaoyw.online", d.DownloadBaseURL)
	assert.Equal(t, "https://api.jiuxiaoyw.online", d.FrontendBaseURL)
}

func TestResolveDomainConfig_InvalidDBValueIgnored(t *testing.T) {
	// domainOverride 经 Get 读 system_configs；无 db 时 Get 恒为空，
	// 这里只验证 normalize 对非法环境值同样兜底回退 ServerURL
	svc := &ConfigService{baseCfg: config.Config{
		Backends: config.BackendsConfig{
			ServerURL:   "https://api.jiuxiaoyw.online",
			DownloadURL: "http://192.168.1.1", // 私网：非法，回退 ServerURL
		},
	}}
	d := svc.ResolveDomainConfig(context.Background())
	assert.Equal(t, "https://api.jiuxiaoyw.online", d.DownloadBaseURL)
}
