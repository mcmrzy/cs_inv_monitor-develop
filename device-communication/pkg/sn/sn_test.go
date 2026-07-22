package sn

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGenerateSN(t *testing.T) {
	date := time.Date(2024, 6, 1, 0, 0, 0, 0, time.UTC)
	info, err := GenerateSN("H1", "CN", "A001", date, 12345)
	require.NoError(t, err)
	assert.Len(t, info.String(), SNLength)
	assert.Equal(t, "H1", info.Manufacturer)
	assert.Equal(t, "CN", info.Country)
	assert.Equal(t, "A001", info.Customer)
	assert.Equal(t, "12345", info.Sequence)
	assert.NotEmpty(t, info.CheckDigit)
}

func TestGenerateSN_InvalidManufacturer(t *testing.T) {
	date := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
	_, err := GenerateSN("XX", "CN", "A001", date, 1)
	assert.Error(t, err)

	_, err = GenerateSN("X", "CN", "A001", date, 1)
	assert.Error(t, err)
}

func TestGenerateSN_InvalidCountry(t *testing.T) {
	date := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
	_, err := GenerateSN("H1", "XX", "A001", date, 1)
	assert.Error(t, err)
}

func TestGenerateSN_InvalidCustomer(t *testing.T) {
	date := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
	_, err := GenerateSN("H1", "CN", "0001", date, 1)
	assert.Error(t, err)

	_, err = GenerateSN("H1", "CN", "A1", date, 1)
	assert.Error(t, err)
}

func TestGenerateSN_InvalidSequence(t *testing.T) {
	date := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
	_, err := GenerateSN("H1", "CN", "A001", date, -1)
	assert.Error(t, err)

	_, err = GenerateSN("H1", "CN", "A001", date, 100000)
	assert.Error(t, err)
}

func TestGenerateSN_YearBounds(t *testing.T) {
	// 2024 是基准年
	_, err := GenerateSN("H1", "CN", "A001", time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC), 1)
	assert.Error(t, err)

	// 遥远的未来超出字符集
	_, err = GenerateSN("H1", "CN", "A001", time.Date(2060, 1, 1, 0, 0, 0, 0, time.UTC), 1)
	assert.Error(t, err)
}

func TestParseSN(t *testing.T) {
	date := time.Date(2024, 6, 1, 0, 0, 0, 0, time.UTC)
	info, err := GenerateSN("H1", "CN", "A001", date, 12345)
	require.NoError(t, err)

	parsed, err := ParseSN(info.String())
	require.NoError(t, err)
	assert.Equal(t, info.Manufacturer, parsed.Manufacturer)
	assert.Equal(t, info.Country, parsed.Country)
	assert.Equal(t, info.Customer, parsed.Customer)
	assert.Equal(t, info.YearMonth, parsed.YearMonth)
	assert.Equal(t, info.Sequence, parsed.Sequence)
	assert.Equal(t, info.CheckDigit, parsed.CheckDigit)
}

func TestParseSN_InvalidLength(t *testing.T) {
	_, err := ParseSN("H1CN1234567890")
	assert.Error(t, err)

	_, err = ParseSN("H1CN1234567890123456")
	assert.Error(t, err)
}

func TestParseSN_InvalidManufacturer(t *testing.T) {
	_, err := ParseSN("X1CN1234567890123")
	assert.Error(t, err)
}

func TestParseSN_InvalidCountry(t *testing.T) {
	_, err := ParseSN("H1XX1234567890123")
	assert.Error(t, err)
}

func TestParseSN_InvalidCustomer(t *testing.T) {
	_, err := ParseSN("H1CN0000567890123")
	assert.Error(t, err)
}

func TestParseSN_InvalidYearCode(t *testing.T) {
	// 第9位（索引8）是年份码，使用非法字符
	_, err := ParseSN("H1CNA001I12345678")
	assert.Error(t, err)
}

func TestParseSN_InvalidMonthCode(t *testing.T) {
	// 第10位（索引9）是月份码，使用非法字符
	_, err := ParseSN("H1CNA0011Z2345678")
	assert.Error(t, err)
}

func TestValidateSN(t *testing.T) {
	date := time.Date(2024, 6, 1, 0, 0, 0, 0, time.UTC)
	info, err := GenerateSN("H1", "CN", "A001", date, 12345)
	require.NoError(t, err)

	assert.True(t, ValidateSN(info.String()))
	assert.False(t, ValidateSN("H1CNA0011A2345678"))
	assert.False(t, ValidateSN("invalid"))
}

func TestGetProductionDate(t *testing.T) {
	date := time.Date(2024, 6, 1, 0, 0, 0, 0, time.UTC)
	info, err := GenerateSN("H1", "CN", "A001", date, 12345)
	require.NoError(t, err)

	prodDate, err := GetProductionDate(info)
	require.NoError(t, err)
	assert.Equal(t, 2024, prodDate.Year())
	assert.Equal(t, time.June, prodDate.Month())
	assert.Equal(t, 1, prodDate.Day())
}

func TestFormatSNForDisplay(t *testing.T) {
	date := time.Date(2024, 6, 1, 0, 0, 0, 0, time.UTC)
	info, err := GenerateSN("H1", "CN", "A001", date, 12345)
	require.NoError(t, err)

	formatted := FormatSNForDisplay(info.String())
	assert.Len(t, formatted, 21) // 16 字符 + 5 个空格
	assert.Contains(t, formatted, " ")

	// 非 16 位应保持原样
	assert.Equal(t, "short", FormatSNForDisplay("short"))
}

func TestCalculateCheckDigit(t *testing.T) {
	// 非 15 位返回 "0"
	assert.Equal(t, "0", CalculateCheckDigit("short"))

	// 合法 15 位应返回单个字符
	digit := CalculateCheckDigit("H1CNA0011A23456")
	assert.Len(t, digit, 1)
}

func TestYearToCode(t *testing.T) {
	code, err := yearToCode(2024)
	require.NoError(t, err)
	assert.Equal(t, "1", code)

	code, err = yearToCode(2025)
	require.NoError(t, err)
	assert.Equal(t, "2", code)

	_, err = yearToCode(2023)
	assert.Error(t, err)
}

func TestCodeToYear(t *testing.T) {
	year, err := codeToYear('1')
	require.NoError(t, err)
	assert.Equal(t, 2024, year)

	year, err = codeToYear('2')
	require.NoError(t, err)
	assert.Equal(t, 2025, year)

	_, err = codeToYear('!')
	assert.Error(t, err)
}

func TestMonthToCode(t *testing.T) {
	assert.Equal(t, "1", monthToCode(time.January))
	assert.Equal(t, "C", monthToCode(time.December))
	assert.Equal(t, "1", monthToCode(time.Month(0)))
	assert.Equal(t, "1", monthToCode(time.Month(13)))
}

func TestCodeToMonth(t *testing.T) {
	month, err := codeToMonth('1')
	require.NoError(t, err)
	assert.Equal(t, time.January, month)

	month, err = codeToMonth('C')
	require.NoError(t, err)
	assert.Equal(t, time.December, month)

	_, err = codeToMonth('Z')
	assert.Error(t, err)
}

func TestSNInfo_String(t *testing.T) {
	info := &SNInfo{
		Manufacturer: "H1",
		Country:      "CN",
		Customer:     "A001",
		YearMonth:    "1A",
		Sequence:     "12345",
		CheckDigit:   "X",
	}
	assert.Equal(t, "H1CNA0011A12345X", info.String())
}
