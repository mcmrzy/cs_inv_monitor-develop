package otamanifest

import (
	"crypto/ed25519"
	"strings"
	"testing"
)

func manifestFields() map[string]string {
	return map[string]string{"manifest_version": "2", "key_id": "release-test", "model": "MODEL", "target": "esp", "version": "1.2.3", "build_number": "12", "board_codes": "COMM-A,COMM-B", "size": "1024", "sha256": strings.Repeat("a", 64), "security_version": "1", "min_bootloader": "1", "storage_layout": "c3-layout-1", "required_capabilities": "ota_manifest_v2_chunked", "dependency_requirements": "arm:MAIN-A:3:1"}
}

func TestCanonicalSignatureBindsBoardAndPurpose(t *testing.T) {
	pub, priv, _ := ed25519.GenerateKey(nil)
	payload, err := Encode(FirmwareManifest, manifestFields())
	if err != nil {
		t.Fatal(err)
	}
	signature := Sign(priv, payload)
	if _, err = Verify(pub, FirmwareManifest, payload, signature); err != nil {
		t.Fatal(err)
	}
	altered := strings.Replace(string(payload), "COMM-A,COMM-B", "COMM-C,COMM-D", 1)
	if _, err = Verify(pub, FirmwareManifest, []byte(altered), signature); err == nil {
		t.Fatal("wrong board signature accepted")
	}
	if _, err = Verify(pub, InstallAuthorization, payload, signature); err == nil {
		t.Fatal("cross purpose signature accepted")
	}
}

func TestRejectAmbiguousAndOverlongPayloads(t *testing.T) {
	payload, err := Encode(FirmwareManifest, manifestFields())
	if err != nil {
		t.Fatal(err)
	}
	for _, bad := range []string{strings.Replace(string(payload), "\n", "\r\n", 1), string(payload) + "target=arm\n", strings.Replace(string(payload), "size=1024", "size=01024", 1), strings.Replace(string(payload), "COMM-A,COMM-B", "COMM-B,COMM-A", 1), strings.Replace(string(payload), "arm:MAIN-A:3:1", "arm:MAIN-A:3:1,arm:MAIN-B:3:1", 1), strings.Repeat("x", MaxObjectBytes+1)} {
		if _, err := Parse(FirmwareManifest, []byte(bad)); err == nil {
			t.Fatalf("ambiguous payload accepted: %.100s", bad)
		}
	}
	fields := manifestFields()
	fields["model"] = "MODEL\ntarget=arm"
	if _, err := Encode(FirmwareManifest, fields); err == nil {
		t.Fatal("newline injection")
	}
	fields = manifestFields()
	fields["extra"] = "x"
	if _, err := Encode(FirmwareManifest, fields); err == nil {
		t.Fatal("extra key")
	}
}

func TestUIDAndSequenceDoNotLosePrecision(t *testing.T) {
	fields := map[string]string{"authorization_version": "1", "key_id": "ota-test", "authorization_id": "auth-1", "operation": "install", "device_uid": strings.Repeat("a", 16), "sn": "SN001", "model": "MODEL", "target": "esp", "board_code": "COMM-A", "board_uid": strings.Repeat("b", 16), "identity_revision": "2", "module_revision": "1", "dependency_identities": "arm:MAIN-A:" + strings.Repeat("c", 16) + ":1", "binding_revision": "3", "firmware_id": "42", "manifest_digest": strings.Repeat("d", 64), "install_sequence": "9007199254740993", "time_policy": "counter_once", "issued_at": "1791950400", "expires_at": "1792209600"}
	payload, err := Encode(InstallAuthorization, fields)
	if err != nil {
		t.Fatal(err)
	}
	parsed, err := Parse(InstallAuthorization, payload)
	if err != nil {
		t.Fatal(err)
	}
	if parsed["install_sequence"] != "9007199254740993" {
		t.Fatal("sequence rounded")
	}
	fields["time_policy"] = "strict_time"
	fields["expires_at"] = fields["issued_at"]
	if _, err := Encode(InstallAuthorization, fields); err == nil {
		t.Fatal("invalid deadline accepted")
	}
}
