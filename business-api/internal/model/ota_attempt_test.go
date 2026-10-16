package model

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestOTACommandTaskIDRoundTrip(t *testing.T) {
	for _, tc := range []struct {
		id    int64
		retry int
		token string
	}{{123, 0, "123"}, {123, 1, "123-r1"}, {9223372036854775807, 2147483647, "9223372036854775807-r2147483647"}} {
		require.Equal(t, tc.token, OTACommandTaskID(tc.id, tc.retry))
		id, retryCount, err := ParseOTACommandTaskID(tc.token)
		require.NoError(t, err)
		require.Equal(t, tc.id, id)
		require.Equal(t, tc.retry, retryCount)
	}
}

func TestOTACommandTaskIDRejectsAmbiguousTokens(t *testing.T) {
	for _, token := range []string{"", "0", "-1", "+1", "01", " 1", "1 ", "1-r0", "1-r-1", "1-r01", "1-r+1", "1-r", "1-r1-r2", "1-x1", "9223372036854775808", "1-r2147483648", "1-r999999999999999999999999999"} {
		_, _, err := ParseOTACommandTaskID(token)
		require.Error(t, err, token)
	}
}
