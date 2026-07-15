package config

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func validConfigForTest() *Config {
	return &Config{
		Server:   ServerConfig{Port: 8081},
		Database: DatabaseConfig{Host: "postgres", Password: "test-password"},
		MQTT: MQTTConfig{
			Broker:      "broker.example.test",
			TLSInsecure: true,
			CertSHA256:  strings.Repeat("a1", 32),
		},
		Backends: BackendsConfig{
			APIServer:   "http://api:8080",
			InternalKey: "test-internal-key",
		},
	}
}

func TestValidateRejectsAllZeroMQTTCertificatePin(t *testing.T) {
	cfg := validConfigForTest()
	cfg.MQTT.CertSHA256 = strings.Repeat("0", 64)

	err := cfg.Validate()
	require.Error(t, err)
	require.Contains(t, err.Error(), "non-placeholder 64-character SHA-256 pin")
}

func TestValidateAcceptsNonPlaceholderMQTTCertificatePin(t *testing.T) {
	cfg := validConfigForTest()
	require.NoError(t, cfg.Validate())
}
