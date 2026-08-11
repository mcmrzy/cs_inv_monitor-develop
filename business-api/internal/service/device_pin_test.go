package service

import (
	"testing"
)

// TestComputeDevicePIN verifies PIN derivation against the firmware/nameplate
// test vectors (D:\CS_INV_WIFI\tools\pin_test_vectors.py, ble_ct_pin.c).
func TestComputeDevicePIN(t *testing.T) {
	vectors := []struct{ sn, want string }{
		{"H1CNA00135000014", "641529"},
		{"H1CNA00135000015", "246969"},
		{"H1CNA00135000016", "213975"},
		{"H1DEA0012A00088X", "359829"},
	}
	for _, v := range vectors {
		if got := computeDevicePIN("CS_INV_L10_2026_SECRET", v.sn); got != v.want {
			t.Errorf("computeDevicePIN(%s) = %s, want %s", v.sn, got, v.want)
		}
	}
}

// TestVerifyDevicePIN checks strict-mode PIN validation: correct pin passes,
// wrong/empty pin fails, missing PRODUCT_SECRET fails closed.
func TestVerifyDevicePIN(t *testing.T) {
	t.Setenv("PRODUCT_SECRET", "CS_INV_L10_2026_SECRET")

	if err := verifyDevicePIN("H1CNA00135000014", "641529"); err != nil {
		t.Errorf("valid pin rejected: %v", err)
	}
	if err := verifyDevicePIN("H1CNA00135000014", "000000"); err == nil {
		t.Error("wrong pin accepted")
	}
	if err := verifyDevicePIN("H1CNA00135000014", ""); err == nil {
		t.Error("empty pin accepted")
	}

	t.Setenv("PRODUCT_SECRET", "")
	if err := verifyDevicePIN("H1CNA00135000014", "641529"); err == nil {
		t.Error("missing PRODUCT_SECRET did not fail closed")
	}
}
