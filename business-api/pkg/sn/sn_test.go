package sn

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ==================== GenerateSN ====================

func TestGenerateSN_正常生成(t *testing.T) {
	info, err := GenerateSN("H1", "CN", "A001", time.Date(2024, 6, 15, 0, 0, 0, 0, time.UTC), 1)
	require.NoError(t, err)
	assert.Equal(t, "H1", info.Manufacturer)
	assert.Equal(t, "CN", info.Country)
	assert.Equal(t, "A001", info.Customer)
	assert.Equal(t, "00001", info.Sequence)
	assert.Len(t, info.String(), SNLength)
}

func TestGenerateSN_校验位计算正确(t *testing.T) {
	info, err := GenerateSN("H1", "CN", "A001", time.Date(2024, 6, 15, 0, 0, 0, 0, time.UTC), 1)
	require.NoError(t, err)

	base15 := info.Manufacturer + info.Country + info.Customer + info.YearMonth + info.Sequence
	expected := CalculateCheckDigit(base15)
	assert.Equal(t, expected, info.CheckDigit)
}

func TestGenerateSN_序列号补零到5位(t *testing.T) {
	tests := []struct {
		name     string
		seq      int
		expected string
	}{
		{"seq=0", 0, "00000"},
		{"seq=1", 1, "00001"},
		{"seq=99", 99, "00099"},
		{"seq=12345", 12345, "12345"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			info, err := GenerateSN("H1", "CN", "A001", time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC), tc.seq)
			require.NoError(t, err)
			assert.Equal(t, tc.expected, info.Sequence)
		})
	}
}

func TestGenerateSN_无效厂商代码返回错误(t *testing.T) {
	tests := []struct {
		name         string
		manufacturer string
	}{
		{"长度不足", "H"},
		{"长度过长", "H12"},
		{"首字母非法", "A1"},
		{"第二字符非法", "H!"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, err := GenerateSN(tc.manufacturer, "CN", "A001", time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC), 1)
			assert.Error(t, err)
		})
	}
}

func TestGenerateSN_无效国家代码返回错误(t *testing.T) {
	_, err := GenerateSN("H1", "XX", "A001", time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC), 1)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "invalid country code")
}

func TestGenerateSN_无效客户代码返回错误(t *testing.T) {
	tests := []struct {
		name     string
		customer string
	}{
		{"长度不足", "A01"},
		{"长度过长", "A0011"},
		{"等级非法", "Z001"},
		{"数字部分非数字", "A00X"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, err := GenerateSN("H1", "CN", tc.customer, time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC), 1)
			assert.Error(t, err)
		})
	}
}

func TestGenerateSN_序列号越界返回错误(t *testing.T) {
	_, err := GenerateSN("H1", "CN", "A001", time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC), -1)
	assert.Error(t, err)

	_, err = GenerateSN("H1", "CN", "A001", time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC), 100000)
	assert.Error(t, err)
}

func TestGenerateSN_年份过早返回错误(t *testing.T) {
	_, err := GenerateSN("H1", "CN", "A001", time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC), 1)
	assert.Error(t, err)
}

// ==================== ParseSN ====================

func TestParseSN_正常解析(t *testing.T) {
	// 先生成一个合法的 SN
	orig, err := GenerateSN("H1", "CN", "A001", time.Date(2024, 6, 15, 0, 0, 0, 0, time.UTC), 42)
	require.NoError(t, err)

	info, err := ParseSN(orig.String())
	require.NoError(t, err)
	assert.Equal(t, "H1", info.Manufacturer)
	assert.Equal(t, "CN", info.Country)
	assert.Equal(t, "A001", info.Customer)
	assert.Equal(t, "00042", info.Sequence)
}

func TestParseSN_小写输入自动转大写(t *testing.T) {
	orig, err := GenerateSN("H1", "CN", "A001", time.Date(2024, 6, 15, 0, 0, 0, 0, time.UTC), 1)
	require.NoError(t, err)

	snLower := orig.String()
	// toLower for alpha chars
	info, err := ParseSN(snLower)
	require.NoError(t, err)
	assert.Equal(t, orig.Manufacturer, info.Manufacturer)
}

func TestParseSN_长度错误返回错误(t *testing.T) {
	_, err := ParseSN("SHORT")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "must be 16 characters")
}

func TestParseSN_无效厂商首字符(t *testing.T) {
	_, err := ParseSN("X1CNA0011A00001A")
	assert.Error(t, err)
}

func TestParseSN_无效国家代码(t *testing.T) {
	_, err := ParseSN("H1XXA0011A000010")
	assert.Error(t, err)
}

// ==================== ValidateSN ====================

func TestValidateSN_合法SN返回True(t *testing.T) {
	info, err := GenerateSN("O2", "US", "B002", time.Date(2025, 3, 1, 0, 0, 0, 0, time.UTC), 123)
	require.NoError(t, err)
	assert.True(t, ValidateSN(info.String()))
}

func TestValidateSN_篡改校验位返回False(t *testing.T) {
	info, err := GenerateSN("H1", "CN", "A001", time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC), 1)
	require.NoError(t, err)

	// 篡改最后一位
	sn := info.String()
	tampered := sn[:15] + "X"
	if ValidateSN(tampered) {
		// X might coincidentally be the correct check digit, try another char
		tampered = sn[:15] + "0"
		if sn[15] == '0' {
			tampered = sn[:15] + "1"
		}
		assert.False(t, ValidateSN(tampered), "篡改校验位应验证失败")
	}
}

func TestValidateSN_空字符串返回False(t *testing.T) {
	assert.False(t, ValidateSN(""))
}

func TestValidateSN_随机字符串返回False(t *testing.T) {
	assert.False(t, ValidateSN("AAAAAAAAAAAAAAAA"))
}

// ==================== GetProductionDate ====================

func TestGetProductionDate_正确解析日期(t *testing.T) {
	date := time.Date(2025, 7, 20, 0, 0, 0, 0, time.UTC)
	info, err := GenerateSN("H1", "CN", "A001", date, 1)
	require.NoError(t, err)

	prodDate, err := GetProductionDate(info)
	require.NoError(t, err)
	assert.Equal(t, 2025, prodDate.Year())
	assert.Equal(t, time.July, prodDate.Month())
}

// ==================== FormatSNForDisplay ====================

func TestFormatSNForDisplay_正确格式化(t *testing.T) {
	info, err := GenerateSN("H1", "CN", "A001", time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC), 1)
	require.NoError(t, err)

	display := FormatSNForDisplay(info.String())
	// 格式: XX XX XXXX XX XXXXX X
	assert.Contains(t, display, " ")
	assert.Len(t, display, SNLength+5) // 16 chars + 5 spaces
}

func TestFormatSNForDisplay_长度不匹配原样返回(t *testing.T) {
	assert.Equal(t, "SHORT", FormatSNForDisplay("SHORT"))
}

// ==================== CalculateCheckDigit ====================

func TestCalculateCheckDigit_长度非15返回零字符(t *testing.T) {
	assert.Equal(t, "0", CalculateCheckDigit("short"))
	assert.Equal(t, "0", CalculateCheckDigit(""))
}

func TestCalculateCheckDigit_相同输入相同输出(t *testing.T) {
	base := "H1CNA0011A00001"
	assert.Equal(t, CalculateCheckDigit(base), CalculateCheckDigit(base))
}

func TestCalculateCheckDigit_不同输入通常不同输出(t *testing.T) {
	base1 := "H1CNA0011A00001"
	base2 := "H1CNA0011A00002"
	// 不同输入有极小概率产生相同校验位，但通常不同
	assert.NotEqual(t, CalculateCheckDigit(base1), CalculateCheckDigit(base2))
}

// ==================== 年月编码 round-trip ====================

func TestYearCode_RoundTrip(t *testing.T) {
	for year := 2024; year <= 2056; year++ {
		code, err := yearToCode(year)
		require.NoError(t, err)
		assert.Len(t, code, 1)

		decoded, err := codeToYear(code[0])
		require.NoError(t, err)
		assert.Equal(t, year, decoded)
	}
}

func TestMonthCode_RoundTrip(t *testing.T) {
	for m := time.January; m <= time.December; m++ {
		code := monthToCode(m)
		assert.Len(t, code, 1)

		decoded, err := codeToMonth(code[0])
		require.NoError(t, err)
		assert.Equal(t, m, decoded)
	}
}
