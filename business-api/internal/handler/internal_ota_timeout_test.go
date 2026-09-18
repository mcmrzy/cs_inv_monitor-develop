package handler

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

// 回归用例覆盖一个真实事故：device_upgrades 的超时收口曾按 started_at 判定
// （15 分钟）。started_at 只在首次进入 downloading/upgrading 时置位、永不刷新，
// 于是 arm/dsp 这类走 9600 baud IAP 串口的慢速升级（256KB 约 4.6 分钟纯传输，
// 加擦除等待与握手重试可达 8 分钟以上）会在中途被判超时置为 failed；此后设备
// 真正的成功回报被 `WHERE status='upgrading'` 守卫静默丢弃，后台永久显示失败。
//
// 现在判据是 updated_at：设备每次上报进度都会刷新它，仍在推进的升级不会被误判。
func TestIsOTAUpgradeRecordStale_进度持续刷新则不判超时(t *testing.T) {
	now := time.Now()
	timeout := 20 * time.Minute

	// 升级已开始 30 分钟（旧实现按 started_at 判会直接认为超时），
	// 但最后一次进度上报是在 30 秒前 —— 新的 updated_at 判据必须放行。
	justReported := now.Add(-30 * time.Second)
	assert.False(t, isOTAUpgradeRecordStale(justReported, timeout, now),
		"进度刚刷新过的记录不应被判超时（旧实现只看 started_at 会误判）")

	// 模拟一次持续上报的长升级：每一分钟评估一次，最后一次上报始终在 30 秒前。
	// 无论升级跑了多久，都不应被判超时（旧实现会在第 15 分钟就收口）。
	upgradeStart := now.Add(-40 * time.Minute)
	for elapsed := time.Duration(0); elapsed < 40*time.Minute; elapsed += time.Minute {
		evalAt := upgradeStart.Add(elapsed)
		lastReport := evalAt.Add(-30 * time.Second)
		assert.False(t, isOTAUpgradeRecordStale(lastReport, timeout, evalAt),
			"持续上报的升级在第 %v 分钟不应被判超时", elapsed.Minutes())
	}
}

func TestIsOTAUpgradeRecordStale_真静默才判超时(t *testing.T) {
	now := time.Now()
	timeout := 20 * time.Minute

	assert.True(t, isOTAUpgradeRecordStale(now.Add(-21*time.Minute), timeout, now),
		"静默超过阈值应判超时")
	assert.False(t, isOTAUpgradeRecordStale(now.Add(-19*time.Minute), timeout, now),
		"未达阈值不应判超时")
}

func TestIsOTAUpgradeRecordStale_阈值非正时禁用(t *testing.T) {
	now := time.Now()
	assert.False(t, isOTAUpgradeRecordStale(now.Add(-100*time.Hour), 0, now),
		"阈值为 0 表示禁用超时收口")
	assert.False(t, isOTAUpgradeRecordStale(now.Add(-100*time.Hour), -1, now),
		"负阈值同样禁用")
}
