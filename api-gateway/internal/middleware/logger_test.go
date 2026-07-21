package middleware

import (
	"net/url"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestRedactedQueryRemovesCredentials(t *testing.T) {
	query := redactedQuery(url.Values{
		"token": {"secret-token"}, "refresh_token": {"refresh-secret"},
		"last_time": {"123"},
	})
	require.NotContains(t, query, "secret-token")
	require.NotContains(t, query, "refresh-secret")
	require.Contains(t, query, "last_time=123")
	require.Contains(t, query, "%5BREDACTED%5D")
}
