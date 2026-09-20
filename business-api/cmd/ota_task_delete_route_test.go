package main

import (
	"os"
	"strings"
	"testing"
)

// 升级任务（/ota/tasks）是现行统一接口，不属于退役的「升级包」写路径。
// 2026-09-15 的 410 退役改造曾把 DELETE /tasks/:id 一并换成 LegacyPackageRetired，
// 导致 Web 端删除任务必然失败，这里固化该路由必须指向真实删除处理器。
func TestUpgradeTaskDeleteRouteIsLive(t *testing.T) {
	source, err := os.ReadFile("main.go")
	if err != nil {
		t.Fatal(err)
	}
	mainSource := string(source)

	const route = `otaGroup.DELETE("/tasks/:id", middleware.RequirePermission(deps.PermChecker, "ota", "delete"), deps.OTAHandler.DeleteUpgradeTask)`
	if !strings.Contains(mainSource, route) {
		t.Fatalf("upgrade task delete route must reach the real handler: %s", route)
	}
}

// 任务子路由（execute/cancel/retry/delete）都不该被 410 退役处理器接管。
func TestUpgradeTaskSubRoutesAreNotRetired(t *testing.T) {
	source, err := os.ReadFile("main.go")
	if err != nil {
		t.Fatal(err)
	}
	for _, line := range strings.Split(string(source), "\n") {
		trimmed := strings.TrimSpace(line)
		if !strings.HasPrefix(trimmed, `otaGroup.`) || !strings.Contains(trimmed, `"/tasks`) {
			continue
		}
		if strings.Contains(trimmed, "LegacyPackageRetired") {
			t.Fatalf("upgrade task route must not be retired: %s", trimmed)
		}
	}
}
