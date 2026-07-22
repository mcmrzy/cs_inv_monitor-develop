package sn

import (
	"fmt"
	"strings"
	"time"
)

const SNLength = 16

const yearCharset = "123456789ABCDEFGHJKLMNPQRSTUVWXYZ"

var monthCodes = []string{"1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C"}

var validCountryCodes = map[string]bool{
	"AF": true, "AL": true, "DZ": true, "AD": true, "AO": true, "AG": true, "AR": true, "AM": true, "AU": true, "AT": true,
	"AZ": true, "BS": true, "BH": true, "BD": true, "BB": true, "BY": true, "BE": true, "BZ": true, "BJ": true, "BT": true,
	"BO": true, "BA": true, "BW": true, "BR": true, "BN": true, "BG": true, "BF": true, "BI": true, "KH": true, "CM": true,
	"CA": true, "CV": true, "CF": true, "TD": true, "CL": true, "CN": true, "CO": true, "KM": true, "CG": true, "CR": true,
	"CI": true, "HR": true, "CU": true, "CY": true, "CZ": true, "DK": true, "DJ": true, "DM": true, "DO": true, "EC": true,
	"EG": true, "SV": true, "GQ": true, "ER": true, "EE": true, "ET": true, "FJ": true, "FI": true, "FR": true, "GA": true,
	"GM": true, "GE": true, "DE": true, "GH": true, "GR": true, "GD": true, "GT": true, "GN": true, "GW": true, "GY": true,
	"HT": true, "HN": true, "HU": true, "IS": true, "IN": true, "ID": true, "IR": true, "IQ": true, "IE": true, "IL": true,
	"IT": true, "JM": true, "JP": true, "JO": true, "KZ": true, "KE": true, "KI": true, "KP": true, "KR": true, "KW": true,
	"KG": true, "LA": true, "LV": true, "LB": true, "LS": true, "LR": true, "LY": true, "LI": true, "LT": true, "LU": true,
	"MK": true, "MG": true, "MW": true, "MY": true, "MV": true, "ML": true, "MT": true, "MH": true, "MR": true, "MU": true,
	"MX": true, "FM": true, "MD": true, "MC": true, "MN": true, "ME": true, "MA": true, "MZ": true, "MM": true, "NA": true,
	"NR": true, "NP": true, "NL": true, "NZ": true, "NI": true, "NE": true, "NG": true, "NO": true, "OM": true, "PK": true,
	"PW": true, "PS": true, "PA": true, "PG": true, "PY": true, "PE": true, "PH": true, "PL": true, "PT": true, "QA": true,
	"RO": true, "RU": true, "RW": true, "KN": true, "LC": true, "VC": true, "WS": true, "SM": true, "ST": true, "SA": true,
	"SN": true, "RS": true, "SC": true, "SL": true, "SG": true, "SK": true, "SI": true, "SB": true, "SO": true, "ZA": true,
	"SS": true, "ES": true, "LK": true, "SD": true, "SR": true, "SE": true, "CH": true, "SY": true, "TW": true, "TJ": true,
	"TZ": true, "TH": true, "TL": true, "TG": true, "TO": true, "TT": true, "TN": true, "TR": true, "TM": true, "TV": true,
	"UG": true, "UA": true, "AE": true, "GB": true, "US": true, "UY": true, "UZ": true, "VU": true, "VE": true, "VN": true,
	"YE": true, "ZM": true, "ZW": true,
	"99": true, "ZZ": true,
}

type SNInfo struct {
	Manufacturer string
	Country      string
	Customer     string
	YearMonth    string
	Sequence     string
	CheckDigit   string
}

func (s *SNInfo) String() string {
	return s.Manufacturer + s.Country + s.Customer + s.YearMonth + s.Sequence + s.CheckDigit
}

func yearToCode(year int) (string, error) {
	base := 2024
	if year < base {
		return "", fmt.Errorf("year %d is before base year %d", year, base)
	}
	n := year - base
	if n >= len(yearCharset) {
		return "", fmt.Errorf("year %d exceeds max supported year", year)
	}
	return string(yearCharset[n]), nil
}

func codeToYear(code byte) (int, error) {
	idx := strings.IndexByte(yearCharset, code)
	if idx < 0 {
		return 0, fmt.Errorf("invalid year code: %c", code)
	}
	return 2024 + idx, nil
}

func monthToCode(month time.Month) string {
	if month >= 1 && month <= 12 {
		return monthCodes[month-1]
	}
	return monthCodes[0]
}

func codeToMonth(code byte) (time.Month, error) {
	for i, mc := range monthCodes {
		if mc[0] == code {
			return time.Month(i + 1), nil
		}
	}
	return 0, fmt.Errorf("invalid month code: %c", code)
}

func crc16modbus(data []byte) uint16 {
	var crc uint16 = 0xFFFF
	for _, b := range data {
		crc ^= uint16(b)
		for j := 0; j < 8; j++ {
			if crc&1 != 0 {
				crc = (crc >> 1) ^ 0xA001
			} else {
				crc = crc >> 1
			}
		}
	}
	return crc
}

func valueToChar(v int) byte {
	if v >= 0 && v <= 9 {
		return byte('0' + v)
	}
	if v >= 10 && v <= 35 {
		return byte('A' + v - 10)
	}
	return '0'
}

func CalculateCheckDigit(base15 string) string {
	if len(base15) != 15 {
		return "0"
	}
	crc := crc16modbus([]byte(base15))
	lo := int(crc & 0xFF)
	return string(valueToChar(lo % 36))
}

func GenerateSN(manufacturer, country, customer string, date time.Time, seq int) (*SNInfo, error) {
	if len(manufacturer) != 2 {
		return nil, fmt.Errorf("manufacturer must be 2 characters, got %d", len(manufacturer))
	}
	mf0 := manufacturer[0]
	if mf0 != 'H' && mf0 != 'O' && mf0 != 'S' {
		return nil, fmt.Errorf("manufacturer first char must be H/O/S, got %c", mf0)
	}
	mf1 := manufacturer[1]
	if !((mf1 >= '0' && mf1 <= '9') || (mf1 >= 'A' && mf1 <= 'Z')) {
		return nil, fmt.Errorf("manufacturer second char must be 0-9 or A-Z, got %c", mf1)
	}

	country = strings.ToUpper(country)
	if !validCountryCodes[country] {
		return nil, fmt.Errorf("invalid country code: %s", country)
	}

	if len(customer) != 4 {
		return nil, fmt.Errorf("customer must be 4 characters, got %d", len(customer))
	}
	custGrade := customer[0]
	if custGrade != 'A' && custGrade != 'B' && custGrade != 'C' && custGrade != 'X' && custGrade != 'P' {
		return nil, fmt.Errorf("customer grade must be A/B/C/X/P, got %c", custGrade)
	}
	custNum := customer[1:]
	for _, ch := range custNum {
		if ch < '0' || ch > '9' {
			return nil, fmt.Errorf("customer number must be digits, got %c", ch)
		}
	}

	yrCode, err := yearToCode(date.Year())
	if err != nil {
		return nil, err
	}
	moCode := monthToCode(date.Month())
	ym := yrCode + moCode

	if seq < 0 || seq > 99999 {
		return nil, fmt.Errorf("sequence must be 0-99999, got %d", seq)
	}
	seqStr := fmt.Sprintf("%05d", seq)

	info := &SNInfo{
		Manufacturer: manufacturer,
		Country:      country,
		Customer:     customer,
		YearMonth:    ym,
		Sequence:     seqStr,
	}
	base15 := manufacturer + country + customer + ym + seqStr
	info.CheckDigit = CalculateCheckDigit(base15)
	return info, nil
}

func ParseSN(sn string) (*SNInfo, error) {
	sn = strings.ToUpper(strings.TrimSpace(sn))
	if len(sn) != SNLength {
		return nil, fmt.Errorf("SN must be %d characters, got %d", SNLength, len(sn))
	}

	info := &SNInfo{
		Manufacturer: sn[0:2],
		Country:      sn[2:4],
		Customer:     sn[4:8],
		YearMonth:    sn[8:10],
		Sequence:     sn[10:15],
		CheckDigit:   sn[15:16],
	}

	mf0 := sn[0]
	if mf0 != 'H' && mf0 != 'O' && mf0 != 'S' {
		return nil, fmt.Errorf("invalid manufacturer code: first char must be H/O/S, got %c", mf0)
	}
	mf1 := sn[1]
	if !((mf1 >= '0' && mf1 <= '9') || (mf1 >= 'A' && mf1 <= 'Z')) {
		return nil, fmt.Errorf("invalid manufacturer code: second char must be 0-9 or A-Z, got %c", mf1)
	}

	if !validCountryCodes[info.Country] {
		return nil, fmt.Errorf("invalid country code: %s", info.Country)
	}

	custGrade := sn[4]
	if custGrade != 'A' && custGrade != 'B' && custGrade != 'C' && custGrade != 'X' && custGrade != 'P' {
		return nil, fmt.Errorf("invalid customer grade: %c", custGrade)
	}
	for i := 5; i < 8; i++ {
		if sn[i] < '0' || sn[i] > '9' {
			return nil, fmt.Errorf("invalid customer digit at position %d: %c", i+1, sn[i])
		}
	}

	if _, err := codeToYear(sn[8]); err != nil {
		return nil, err
	}
	if _, err := codeToMonth(sn[9]); err != nil {
		return nil, err
	}

	for i := 10; i < 15; i++ {
		if sn[i] < '0' || sn[i] > '9' {
			return nil, fmt.Errorf("invalid sequence digit at position %d: %c", i+1, sn[i])
		}
	}

	if sn[15] < '0' || sn[15] > 'Z' || (sn[15] > '9' && sn[15] < 'A') {
		return nil, fmt.Errorf("invalid check digit: %c", sn[15])
	}

	return info, nil
}

func ValidateSN(sn string) bool {
	info, err := ParseSN(sn)
	if err != nil {
		return false
	}
	base15 := info.Manufacturer + info.Country + info.Customer + info.YearMonth + info.Sequence
	expectedCheck := CalculateCheckDigit(base15)
	return expectedCheck == info.CheckDigit
}

func GetProductionDate(info *SNInfo) (time.Time, error) {
	year, err := codeToYear(info.YearMonth[0])
	if err != nil {
		return time.Time{}, err
	}
	month, err := codeToMonth(info.YearMonth[1])
	if err != nil {
		return time.Time{}, err
	}
	return time.Date(year, month, 1, 0, 0, 0, 0, time.UTC), nil
}

func FormatSNForDisplay(sn string) string {
	if len(sn) != SNLength {
		return sn
	}
	return sn[0:2] + " " + sn[2:4] + " " + sn[4:8] + " " + sn[8:10] + " " + sn[10:15] + " " + sn[15:16]
}
