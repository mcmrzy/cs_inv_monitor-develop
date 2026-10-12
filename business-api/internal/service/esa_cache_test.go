package service

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// 基础套餐不支持 ignoreparams，发布必须使用普通 URL 刷新并覆盖已知参数。
func TestESACachePurger_RefreshUsesFileQuota(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := r.ParseForm(); err != nil {
			t.Fatal(err)
		}
		if got := r.Form.Get("Type"); got != "file" {
			t.Errorf("purge type=%q, want file", got)
		}
		var content struct {
			Files []string `json:"Files"`
		}
		if err := json.Unmarshal([]byte(r.Form.Get("Content")), &content); err != nil {
			t.Fatal(err)
		}
		for _, want := range []string{"https://download.jiuxiaoyw.online/download", "https://download.jiuxiaoyw.online/download.html", "https://download.jiuxiaoyw.online/app-release-info?platform=android"} {
			if !strings.Contains(strings.Join(content.Files, "\n"), want) {
				t.Errorf("missing URL %s", want)
			}
		}
		w.Header().Set("Content-Type", "application/json")
		io.WriteString(w, `{"TaskId":"test-task"}`)
	}))
	defer server.Close()
	p := NewESACachePurger("ak", "sk", "999", "", "")
	p.endpoint = server.URL
	if err := p.Refresh(); err != nil {
		t.Fatal(err)
	}
}

func TestDesiredESACacheRules_DownloadHTMLBypassesCache(t *testing.T) {
	for _, rule := range desiredESACacheRules() {
		if rule.Name == "cs-spa-follow-origin" {
			if rule.EdgeCacheMode != "no_cache" || rule.BrowserCacheMode != "no_cache" {
				t.Errorf("HTML must bypass cache: %+v", rule)
			}
			if !strings.Contains(rule.Rule, `"/download.html"`) {
				t.Error("independent download HTML missing from cache rule")
			}
			return
		}
	}
	t.Fatal("download HTML rule missing")
}

func TestESACachePurger_ReadOperationsUseGET(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			t.Errorf("ESA read operation method=%s, want GET", r.Method)
			w.WriteHeader(http.StatusForbidden)
			io.WriteString(w, `{"Code":"UnsupportedHTTPMethod","Message":"GET required"}`)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		io.WriteString(w, `{"Configs":[{"RuleName":"cs-spa-follow-origin","ConfigId":395386449776640}],"Sites":[]}`)
	}))
	defer server.Close()
	p := NewESACachePurger("ak", "sk", "999", "", "")
	p.endpoint = server.URL
	if _, err := p.ListSites(); err != nil {
		t.Error(err)
	}
	rules, err := p.listCacheRulesByName()
	if err != nil {
		t.Error(err)
	}
	if rules["cs-spa-follow-origin"] != "395386449776640" {
		t.Errorf("existing rule ID not parsed correctly: %v", rules)
	}
}

func TestESACachePurger_EnabledRequiresKeysAndSiteID(t *testing.T) {
	if NewESACachePurger("", "", "1", "", "").Enabled() {
		t.Fatal("empty ak should disable")
	}
	if NewESACachePurger("ak", "", "1", "", "").Enabled() {
		t.Fatal("empty sk should disable")
	}
	if NewESACachePurger("ak", "sk", "", "", "").Enabled() {
		t.Fatal("empty site id should disable")
	}
	if !NewESACachePurger("ak", "sk", "1", "", "").Enabled() {
		t.Fatal("all set should enable")
	}
}

func TestNewESACachePurgerFromConfig_NoopWhenIncomplete(t *testing.T) {
	if _, ok := NewESACachePurgerFromConfig("ak", "sk", "", "", "").(NoopCachePurger); !ok {
		t.Fatal("missing site id should be Noop")
	}
	if _, ok := NewESACachePurgerFromConfig("ak", "sk", "9", "", "").(*ESACachePurger); !ok {
		t.Fatal("full config should be ESA purger")
	}
}

func TestESACachePurger_BuildRefreshPaths(t *testing.T) {
	p := NewESACachePurger("ak", "sk", "999", "https://download.jiuxiaoyw.online", "")
	paths := p.RefreshPaths()
	want := []string{
		"https://download.jiuxiaoyw.online/app-release-info",
		"https://download.jiuxiaoyw.online/app-release-info?platform=android",
		"https://download.jiuxiaoyw.online/api/v1/ota/app/latest",
		"https://download.jiuxiaoyw.online/api/v1/ota/app/latest?platform=android",
		// SPA 入口：边缘毒 301 会让手机输裸域名时报重定向过多。
		"https://download.jiuxiaoyw.online/",
		"https://download.jiuxiaoyw.online/download",
		"https://download.jiuxiaoyw.online/download.html",
		// api 域权威端点：下载页优先请求它，发布后必须一并刷新。
		"https://api.jiuxiaoyw.online/api/v1/ota/app/latest",
		"https://api.jiuxiaoyw.online/api/v1/ota/app/latest?platform=android",
	}
	if len(paths) != len(want) {
		t.Fatalf("len=%d want %d: %v", len(paths), len(want), paths)
	}
	for i := range want {
		if paths[i] != want[i] {
			t.Fatalf("path[%d]=%s want %s", i, paths[i], want[i])
		}
	}
}

func TestESACachePurger_APIHostOverride(t *testing.T) {
	p := NewESACachePurger("ak", "sk", "999", "download.jiuxiaoyw.online", "https://api.example.com")
	paths := p.RefreshPaths()
	want := []string{
		"https://api.example.com/api/v1/ota/app/latest",
		"https://api.example.com/api/v1/ota/app/latest?platform=android",
	}
	for _, w := range want {
		found := false
		for _, path := range paths {
			if path == w {
				found = true
				break
			}
		}
		if !found {
			t.Fatalf("missing %s in %v", w, paths)
		}
	}
}

func TestESACachePurger_RefreshSkipWhenDisabled(t *testing.T) {
	p := NewESACachePurger("", "", "", "", "")
	if err := p.Refresh(); err != nil {
		t.Fatalf("disabled should no-op, got %v", err)
	}
	p.RefreshAsync() // must not panic
}

func TestNoopCachePurger(t *testing.T) {
	var n CachePurger = NoopCachePurger{}
	if n.Enabled() {
		t.Fatal("noop should be disabled")
	}
	n.RefreshAsync()
	n.EnsureCacheRulesAsync()
}

func TestDesiredESACacheRules(t *testing.T) {
	rules := desiredESACacheRules()
	if len(rules) < 3 {
		t.Fatalf("want at least 3 rules, got %d", len(rules))
	}
	foundAPI := false
	for _, r := range rules {
		if strings.Contains(r.Rule, "eq(") {
			t.Errorf("rule %s uses a function instead of ESA's eq operator: %s", r.Name, r.Rule)
		}
		if r.Name == "cs-api-no-store" {
			foundAPI = true
			// ESA 2024-09-10 枚举是 no_cache，旧 CDN 的 off 会被拒绝。
			if r.EdgeCacheMode != "no_cache" {
				t.Fatalf("api rule edge mode=%s", r.EdgeCacheMode)
			}
			if r.BrowserCacheMode != "no_cache" {
				t.Fatalf("api rule browser mode=%s", r.BrowserCacheMode)
			}
		}
		if r.EdgeCacheMode == "off" || r.BrowserCacheMode == "off" {
			t.Fatalf("rule %s still uses invalid mode off", r.Name)
		}
	}
	if !foundAPI {
		t.Fatal("missing cs-api-no-store rule")
	}
}
