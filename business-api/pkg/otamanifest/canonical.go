// Package otamanifest defines bounded, purpose-separated OTA signature payloads.
// It does not turn device-reported metadata into trusted hardware identity.
package otamanifest

import (
	"bytes"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

type Kind string

const (
	FirmwareManifest     Kind = "CS_INV_OTA_V2"
	InstallAuthorization Kind = "CS_INV_INSTALL_AUTH_V1"
	FactoryIdentity      Kind = "CS_INV_FACTORY_ID_V1"
	BindingState         Kind = "CS_INV_BINDING_STATE_V1"
	CancelAuthorization  Kind = "CS_INV_CANCEL_AUTH_V1"
	IdentityChallenge    Kind = "CS_INV_IDENTITY_CHALLENGE_V1"
	InstallResult        Kind = "CS_INV_INSTALL_RESULT_V1"
	MaxObjectBytes            = 4096
)

var schemas = map[Kind][]string{
	FirmwareManifest:     {"manifest_version", "key_id", "model", "target", "version", "build_number", "board_codes", "size", "sha256", "security_version", "min_bootloader", "storage_layout", "required_capabilities", "dependency_requirements"},
	InstallAuthorization: {"authorization_version", "key_id", "authorization_id", "operation", "device_uid", "sn", "model", "target", "board_code", "board_uid", "identity_revision", "module_revision", "dependency_identities", "binding_revision", "firmware_id", "manifest_digest", "install_sequence", "time_policy", "issued_at", "expires_at"},
	FactoryIdentity:      {"identity_version", "key_id", "device_uid", "sn", "model", "expected_identity_revision", "identity_revision", "modules", "device_public_key", "device_key_id"},
	BindingState:         {"binding_version", "key_id", "device_uid", "sn", "binding_revision", "binding_state", "credential_revision"},
	CancelAuthorization:  {"cancel_version", "key_id", "cancel_id", "authorization_id", "device_uid", "sn", "target", "manifest_digest", "install_sequence", "reason"},
	IdentityChallenge:    {"challenge_version", "device_key_id", "challenge", "session_context", "device_uid", "sn", "model", "identity_revision", "modules", "binding_revision", "target", "board_uid", "module_revision", "accepted_sequence", "active_authorization_id", "active_state", "result_digest"},
	InstallResult:        {"result_version", "device_key_id", "authorization_id", "operation", "device_uid", "sn", "target", "board_uid", "identity_revision", "module_revision", "binding_revision", "manifest_digest", "install_sequence", "state", "observed_version", "observed_build_number", "observed_sha256", "health_result", "reason"},
}
var token = regexp.MustCompile(`^[A-Za-z0-9._+-]{1,100}$`)
var board = regexp.MustCompile(`^[A-Z0-9][A-Z0-9._-]{0,49}$`)
var uid = regexp.MustCompile(`^[0-9a-f]{16,64}$`)
var digest = regexp.MustCompile(`^[0-9a-f]{64}$`)

func Encode(kind Kind, fields map[string]string) ([]byte, error) {
	keys, ok := schemas[kind]
	if !ok {
		return nil, errors.New("unknown OTA signature purpose")
	}
	if len(fields) != len(keys) {
		return nil, errors.New("unexpected or missing signature fields")
	}
	var b strings.Builder
	b.WriteString(string(kind))
	b.WriteByte('\n')
	for _, key := range keys {
		value, exists := fields[key]
		if !exists {
			return nil, fmt.Errorf("missing %s", key)
		}
		if err := validateField(kind, key, value); err != nil {
			return nil, fmt.Errorf("%s: %w", key, err)
		}
		b.WriteString(key)
		b.WriteByte('=')
		b.WriteString(value)
		b.WriteByte('\n')
	}
	if kind == InstallAuthorization {
		issued, _ := strconv.ParseUint(fields["issued_at"], 10, 64)
		expires, _ := strconv.ParseUint(fields["expires_at"], 10, 64)
		if issued == 0 || expires <= issued {
			return nil, errors.New("invalid authorization time window")
		}
	}
	// The signature itself must also fit in the bounded object.
	if b.Len()+base64.StdEncoding.EncodedLen(ed25519.SignatureSize) > MaxObjectBytes {
		return nil, errors.New("OTA signature object too large")
	}
	return []byte(b.String()), nil
}

func Parse(kind Kind, payload []byte) (map[string]string, error) {
	keys, ok := schemas[kind]
	if !ok || len(payload) == 0 || len(payload) > MaxObjectBytes || bytes.ContainsRune(payload, '\r') {
		return nil, errors.New("invalid OTA payload")
	}
	lines := strings.Split(string(payload), "\n")
	if len(lines) != len(keys)+2 || lines[0] != string(kind) || lines[len(lines)-1] != "" {
		return nil, errors.New("noncanonical OTA payload")
	}
	fields := make(map[string]string, len(keys))
	for i, key := range keys {
		prefix := key + "="
		if !strings.HasPrefix(lines[i+1], prefix) {
			return nil, errors.New("signature field order mismatch")
		}
		fields[key] = strings.TrimPrefix(lines[i+1], prefix)
	}
	canonical, err := Encode(kind, fields)
	if err != nil {
		return nil, err
	}
	if !bytes.Equal(payload, canonical) {
		return nil, errors.New("noncanonical OTA payload")
	}
	return fields, nil
}

func Sign(key ed25519.PrivateKey, payload []byte) string {
	if len(key) != ed25519.PrivateKeySize {
		return ""
	}
	return base64.StdEncoding.EncodeToString(ed25519.Sign(key, payload))
}

func Verify(key ed25519.PublicKey, kind Kind, payload []byte, signature string) (map[string]string, error) {
	fields, err := Parse(kind, payload)
	if err != nil {
		return nil, err
	}
	sig, err := base64.StdEncoding.Strict().DecodeString(signature)
	if err != nil || len(sig) != ed25519.SignatureSize || base64.StdEncoding.EncodeToString(sig) != signature || len(key) != ed25519.PublicKeySize || !ed25519.Verify(key, payload, sig) {
		return nil, errors.New("invalid OTA signature")
	}
	return fields, nil
}

func Digest(payload []byte) string { sum := sha256.Sum256(payload); return hex.EncodeToString(sum[:]) }

func numeric(v string, bits int) error {
	if v == "" || (len(v) > 1 && v[0] == '0') || strings.HasPrefix(v, "+") {
		return errors.New("noncanonical integer")
	}
	_, err := strconv.ParseUint(v, 10, bits)
	return err
}
func oneOf(v string, allowed ...string) error {
	for _, a := range allowed {
		if v == a {
			return nil
		}
	}
	return errors.New("unsupported value")
}
func validateField(kind Kind, key, value string) error {
	if strings.ContainsAny(value, "\r\n\x00") || len(value) > 2048 {
		return errors.New("invalid field length or newline")
	}
	switch key {
	case "manifest_version":
		return oneOf(value, "2")
	case "authorization_version", "identity_version", "binding_version", "cancel_version", "challenge_version", "result_version":
		return oneOf(value, "1")
	case "target":
		return oneOf(value, "arm", "bms", "dsp", "esp")
	case "operation":
		return oneOf(value, "install", "rollback")
	case "time_policy":
		return oneOf(value, "counter_once", "strict_time")
	case "binding_state":
		return oneOf(value, "bound", "unbound")
	case "active_state":
		return oneOf(value, "idle", "reserved", "receiving", "in_progress", "recovery_required")
	case "health_result":
		return oneOf(value, "pass", "fail", "unknown")
	case "state":
		return oneOf(value, "not_received", "reserved", "receiving", "in_progress", "succeeded", "failed", "cancelled", "recovery_required", "verification_pending")
	case "board_code":
		if !board.MatchString(value) {
			return errors.New("invalid board code")
		}
		return nil
	case "device_uid", "board_uid":
		if !uid.MatchString(value) || len(value)%2 != 0 {
			return errors.New("invalid UID")
		}
		return nil
	case "sha256", "manifest_digest", "challenge", "session_context", "device_public_key":
		if !digest.MatchString(value) {
			return errors.New("invalid digest/key")
		}
		return nil
	case "observed_sha256", "result_digest":
		if value != "" && !digest.MatchString(value) {
			return errors.New("invalid digest")
		}
		return nil
	case "build_number", "security_version", "min_bootloader", "observed_build_number":
		return numeric(value, 32)
	case "size", "identity_revision", "module_revision", "binding_revision", "firmware_id", "install_sequence", "issued_at", "expires_at":
		if err := numeric(value, 64); err != nil {
			return err
		}
		if value == "0" {
			return errors.New("positive integer required")
		}
		return nil
	case "expected_identity_revision", "accepted_sequence", "credential_revision":
		return numeric(value, 64)
	case "board_codes":
		return validateTokens(value, 16, false, true)
	case "required_capabilities":
		return validateTokens(value, 16, true, false)
	case "modules", "dependency_identities", "dependency_requirements":
		return validateRecords(key, value)
	case "observed_version", "active_authorization_id", "reason":
		if value == "" && (key != "reason" || kind == InstallResult) {
			return nil
		}
	}
	if !token.MatchString(value) {
		return errors.New("invalid ASCII token")
	}
	if (key == "version" || key == "observed_version") && len(value) > 31 {
		return errors.New("version too long")
	}
	if key == "sn" && len(value) > 64 {
		return errors.New("SN too long")
	}
	return nil
}

func validateTokens(value string, limit int, empty, boards bool) error {
	if value == "" && empty {
		return nil
	}
	parts := strings.Split(value, ",")
	if len(parts) > limit {
		return errors.New("too many tokens")
	}
	if !sort.StringsAreSorted(parts) {
		return errors.New("unsorted tokens")
	}
	for i, p := range parts {
		if (boards && !board.MatchString(p)) || (!boards && !token.MatchString(p)) || (i > 0 && p == parts[i-1]) {
			return errors.New("invalid or duplicate token")
		}
	}
	return nil
}

func validateRecords(key, value string) error {
	if value == "" && key != "modules" {
		return nil
	}
	records := strings.Split(value, ",")
	if len(records) > 4 {
		return errors.New("too many module records")
	}
	previous := ""
	for _, record := range records {
		p := strings.Split(record, ":")
		if len(p) != 4 || oneOf(p[0], "arm", "bms", "dsp", "esp") != nil || p[0] <= previous || !board.MatchString(p[1]) {
			return errors.New("invalid, unsorted or duplicate module record")
		}
		previous = p[0]
		if key == "dependency_requirements" {
			if numeric(p[2], 32) != nil || numeric(p[3], 32) != nil {
				return errors.New("invalid dependency version")
			}
		} else {
			if !uid.MatchString(p[2]) || len(p[2])%2 != 0 || numeric(p[3], 64) != nil || p[3] == "0" {
				return errors.New("invalid module identity")
			}
		}
	}
	return nil
}
