package middleware

import (
	"testing"
	"time"
)

// 模拟 probe_ratelimit.js 实验1：连续无间隔 250 个请求
// 预期：burst=200 时恰好 200 个通过
func TestTokenBucketBurstProbe(t *testing.T) {
	limiter := newClientLimiter(100, 200)
	b := limiter.get("probe-ip")

	ok, fail := 0, 0
	for i := 0; i < 250; i++ {
		if b.allow() {
			ok++
		} else {
			fail++
		}
	}
	t.Logf("连续250: 200=%d 429=%d（配置 rate=100 burst=200）", ok, fail)
	if ok < 190 || ok > 200 {
		t.Errorf("burst 异常: 期望 ~200, 实际 %d", ok)
	}
}

// 模拟 probe 实验2：固定间隔 50ms 持续 20s（等价 400 个请求）
// 预期：rate=100/s 时全部通过
func TestTokenBucketRateProbe(t *testing.T) {
	limiter := newClientLimiter(100, 200)
	b := limiter.get("probe-ip")

	ok, fail := 0, 0
	start := time.Now()
	for i := 0; i < 400; i++ {
		if b.allow() {
			ok++
		} else {
			fail++
		}
		time.Sleep(50 * time.Millisecond)
	}
	dur := time.Since(start).Seconds()
	t.Logf("50ms间隔×400: 200=%d 429=%d 通过率=%.1f/s（配置 rate=100）", ok, fail, float64(ok)/dur)
	if fail > 0 {
		t.Errorf("rate 异常: 20/s 持续不应失败, 实际失败 %d", fail)
	}
}

// 模拟 probe 实验4：10ms 间隔（100/s）持续 10s
// 预期：rate=100/s 时基本全部通过（可能有极小抖动）
func TestTokenBucketRate100Probe(t *testing.T) {
	limiter := newClientLimiter(100, 200)
	b := limiter.get("probe-ip")

	ok, fail := 0, 0
	for i := 0; i < 1000; i++ {
		if b.allow() {
			ok++
		} else {
			fail++
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Logf("10ms间隔×1000: 200=%d 429=%d", ok, fail)
	if fail > 50 {
		t.Errorf("rate 异常: 100/s 持续不应大比例失败, 实际失败 %d", fail)
	}
}
