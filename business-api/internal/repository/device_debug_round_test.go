package repository

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestRoundDebugMetric 覆盖 REAL(float32) 表示噪声的规整：
// 51.2 存进 float32 列后读出来是 51.20000076293945，直传前端会显示成长浮点。
func TestRoundDebugMetric(t *testing.T) {
	cases := []struct {
		name string
		in   *float64
		want *float64
	}{
		{name: "nil 保持 nil（断线语义）", in: nil, want: nil},
		{name: "float32 正噪声", in: fptr(51.20000076293945), want: fptr(51.2)},
		{name: "float32 负噪声", in: fptr(229.8000030517578), want: fptr(229.8)},
		{name: "大值噪声", in: fptr(145.1999969482422), want: fptr(145.2)},
		{name: "整数值不受影响", in: fptr(380.5), want: fptr(380.5)},
		{name: "三位小数保留", in: fptr(4.812), want: fptr(4.812)},
		{name: "第四位四舍五入", in: fptr(4.81234), want: fptr(4.812)},
		{name: "负数保留符号", in: fptr(-9.500000190734863), want: fptr(-9.5)},
		{name: "极小数归一为 0（避免 JSON -0）", in: fptr(-0.0000001), want: fptr(0)},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := roundDebugMetric(tc.in)
			if tc.want == nil {
				assert.Nil(t, got)
				return
			}
			require.NotNil(t, got)
			assert.Equal(t, *tc.want, *got)
		})
	}
}

func fptr(v float64) *float64 { return &v }
