package handler

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

// reconcile 的"版本变化"判定依赖升级前基线。回归用例覆盖一个真实事故：
// 基线若在 devices upsert 之后读取，oldVersion 会等于 reported，第二条分支
// 恒为假，设备实际升级成功却落到超时分支被误判 failed（后台显示失败、设备
// 已是新版本）。见 DeviceInfo 中基线必须在 upsert 之前读取的约束。
func TestDecideReconcileResult_版本变化判成功(t *testing.T) {
	now := time.Now()
	started := now.Add(-1 * time.Minute)

	// 目标版本号对不上（firmware_versions 缺行 / 格式差异），但设备版本确实变了。
	got := decideReconcileResult("1.6.0", "", "1.5.10", started, now)
	assert.Equal(t, "success", got, "版本已变化但目标号匹配不上时应判成功，而非落到超时分支")
}

func TestDecideReconcileResult_基线未变化且超时判失败(t *testing.T) {
	now := time.Now()
	started := now.Add(-10 * time.Minute)

	got := decideReconcileResult("1.5.10", "1.6.0", "1.5.10", started, now)
	assert.Equal(t, "failed", got, "版本未变化且已超时，应判失败")
}

func TestDecideReconcileResult_目标版本精确匹配判成功(t *testing.T) {
	now := time.Now()
	started := now.Add(-1 * time.Minute)

	// 版本号前缀带 V，matchFirmwareVersion 需归一化后命中。
	got := decideReconcileResult("V1.6.0", "1.6.0", "1.5.10", started, now)
	assert.Equal(t, "success", got)
}

func TestDecideReconcileResult_证据不足保持原状(t *testing.T) {
	now := time.Now()

	// 设备尚未上报版本、且未超时：不应擅自改判。
	got := decideReconcileResult("", "1.6.0", "", now.Add(-1*time.Minute), now)
	assert.Equal(t, "", got, "证据不足时应返回空串，保持 upgrading 原状")

	// 设备尚未上报版本、但已超时：此时才允许判失败。
	got = decideReconcileResult("", "1.6.0", "", now.Add(-10*time.Minute), now)
	assert.Equal(t, "failed", got)
}

// 基线读取时序的反向验证：若 oldVersion 被误传成与 reported 相同（即 upsert
// 之后才读基线），第二条分支失效，这里必须体现出"会误判失败"这一后果。
func TestDecideReconcileResult_基线读晚了会误判(t *testing.T) {
	now := time.Now()
	started := now.Add(-10 * time.Minute)

	// 正确基线：判成功。
	correct := decideReconcileResult("1.6.0", "", "1.5.10", started, now)
	assert.Equal(t, "success", correct)

	// 被 upsert 覆盖后的"基线"（等于 reported）：掉进超时分支误判失败。
	stale := decideReconcileResult("1.6.0", "", "1.6.0", started, now)
	assert.Equal(t, "failed", stale, "这条断言记录了基线读晚了的后果，用于说明为何必须在 upsert 前读取")
}
