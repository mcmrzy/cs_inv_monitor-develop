package service

import (
	"testing"
)

func TestESACachePurger_EnabledRequiresKeysAndSiteID(t *testing.T) {
	if NewESACachePurger("", "", "1", "").Enabled() {
		t.Fatal("empty ak should disable")
	}
	if NewESACachePurger("ak", "", "1", "").Enabled() {
		t.Fatal("empty sk should disable")
	}
	if NewESACachePurger("ak", "sk", "", "").Enabled() {
		t.Fatal("empty site id should disable")
	}
	if !NewESACachePurger("ak", "sk", "1", "").Enabled() {
		t.Fatal("all set should enable")
	}
}

func TestNewESACachePurgerFromConfig_NoopWhenIncomplete(t *testing.T) {
	if _, ok := NewESACachePurgerFromConfig("ak", "sk", "", "").(NoopCachePurger); !ok {
		t.Fatal("missing site id should be Noop")
	}
	if _, ok := NewESACachePurgerFromConfig("ak", "sk", "9", "").(*ESACachePurger); !ok {
		t.Fatal("full config should be ESA purger")
	}
}

func TestESACachePurger_BuildRefreshPaths(t *testing.T) {
	p := NewESACachePurger("ak", "sk", "999", "https://download.jiuxiaoyw.online")
	paths := p.RefreshPaths()
	want := []string{
		"https://download.jiuxiaoyw.online/app-release-info",
		"https://download.jiuxiaoyw.online/api/v1/ota/app/latest",
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

func TestESACachePurger_RefreshSkipWhenDisabled(t *testing.T) {
	p := NewESACachePurger("", "", "", "")
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
		if r.Name == "cs-api-no-store" {
			foundAPI = true
			if r.EdgeCacheMode != "off" {
				t.Fatalf("api rule edge mode=%s", r.EdgeCacheMode)
			}
		}
	}
	if !foundAPI {
		t.Fatal("missing cs-api-no-store rule")
	}
}
