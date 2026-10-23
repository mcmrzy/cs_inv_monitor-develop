package repository

import (
	"math"
	"testing"
)

func TestStationGridPower(t *testing.T) {
	ptr := func(v float64) *float64 { return &v }
	for _, tc := range []struct {
		name                string
		input, charge, want *float64
	}{
		{"supply and charging", ptr(1200), ptr(600), ptr(1800)},
		{"charging only", nil, ptr(600), ptr(600)},
		{"measured zero", ptr(0), nil, ptr(0)},
		{"missing", nil, nil, nil},
		{"invalid", ptr(math.NaN()), ptr(math.Inf(1)), nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := stationGridPower(tc.input, tc.charge)
			if tc.want == nil {
				if got != nil {
					t.Fatalf("want unknown, got %v", *got)
				}
				return
			}
			if got == nil || *got != *tc.want {
				t.Fatalf("got %v, want %v", got, *tc.want)
			}
		})
	}
}
