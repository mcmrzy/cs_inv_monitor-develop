package main

import (
	"bytes"
	"context"
	"testing"

	"github.com/stretchr/testify/assert"

	"inv-api-server/internal/config"
)

func TestRunRejectsUnknownAndReservedCommandsWithoutDatabase(t *testing.T) {
	tests := []struct {
		name string
		args []string
		code int
	}{
		{name: "unknown", args: []string{"unknown"}, code: exitUsage},
		{name: "reserved asset backfill", args: []string{"backfill-assets"}, code: exitReserved},
		{name: "reserved validation", args: []string{"validate-constraints"}, code: exitReserved},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			var stdout, stderr bytes.Buffer
			assert.Equal(t, tc.code, run(context.Background(), tc.args, &stdout, &stderr))
			assert.Empty(t, stdout.String())
			assert.NotEmpty(t, stderr.String())
		})
	}
}

func TestValidateDatabaseConfigRejectsPlaceholderPasswordPrefixes(t *testing.T) {
	base := config.DatabaseConfig{Host: "localhost", Port: 5432, User: "postgres", Database: "inv", SSLMode: "disable"}
	for _, password := range []string{"", "CHANGE_ME", "CHANGE_ME_STRONG_PASSWORD", "change_me_rotate_credential"} {
		candidate := base
		candidate.Password = password
		assert.Error(t, validateDatabaseConfig(candidate), password)
	}
	valid := base
	valid.Password = "a-real-secret"
	assert.NoError(t, validateDatabaseConfig(valid))
}

func TestParseOptionsRequiresExplicitMappingAndApply(t *testing.T) {
	var stderr bytes.Buffer
	_, err := parseOptions("preflight", nil, &stderr)
	assert.ErrorContains(t, err, "--mapping is required")

	options, err := parseOptions("backfill-organizations", []string{"--mapping", "mapping.json", "--batch-size", "50"}, &stderr)
	assert.NoError(t, err)
	assert.False(t, options.apply)
	assert.Equal(t, 50, options.batchSize)
}
