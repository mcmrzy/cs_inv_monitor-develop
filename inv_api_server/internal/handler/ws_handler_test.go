package handler

import (
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestWSOriginPolicyRejectsUnknownBrowserOrigins(t *testing.T) {
	handler := NewWSHandler(nil, nil, nil, nil, []string{"https://cloud.example.com"})

	allowed := httptest.NewRequest("GET", "http://api.example.com/ws", nil)
	allowed.Header.Set("Origin", "https://cloud.example.com")
	require.True(t, handler.checkOrigin(allowed))

	unknown := httptest.NewRequest("GET", "http://api.example.com/ws", nil)
	unknown.Header.Set("Origin", "https://evil.example")
	require.False(t, handler.checkOrigin(unknown))

	native := httptest.NewRequest("GET", "http://api.example.com/ws", nil)
	require.True(t, handler.checkOrigin(native))
}
