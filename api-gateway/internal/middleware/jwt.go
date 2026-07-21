package middleware

import (
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	jwt "github.com/golang-jwt/jwt/v5"
)

const (
	DefaultJWTIssuer       = "inv-api-server"
	DefaultAccessAudience  = "inv-platform-api"
	currentJWTTokenVersion = int64(2)
)

// JWTAuthConfig defines the token profile accepted by normal business routes.
// Refresh and break-glass tokens use different audiences and token types.
type JWTAuthConfig struct {
	Secret   string
	Issuer   string
	Audience string
	Leeway   time.Duration
}

// AccessTokenClaims is deliberately typed so missing, malformed and lossy
// numeric identity claims cannot silently become trusted headers.
type AccessTokenClaims struct {
	TokenVersion         int64  `json:"token_version"`
	TokenType            string `json:"token_type"`
	UserID               int64  `json:"user_id"`
	RootTenantID         int64  `json:"root_tenant_id"`
	OrganizationID       int64  `json:"organization_id"`
	MembershipID         int64  `json:"membership_id"`
	MembershipVersion    int64  `json:"membership_version"`
	SessionVersion       int64  `json:"session_version"`
	SessionID            string `json:"session_id"`
	AuthorizationVersion int64  `json:"authorization_version"`
	Phone                string `json:"phone,omitempty"`
	Role                 *int   `json:"role,omitempty"`
	jwt.RegisteredClaims
}

// publicPaths and publicPrefixes are shared with RBAC's public-path check.
var publicPaths = map[string]bool{
	"/health":                      true,
	"/metrics":                     true,
	"/api/docs":                    true,
	"/api/v1/auth/login":           true,
	"/api/v1/auth/register":        true,
	"/api/v1/auth/send-code":       true,
	"/api/v1/auth/reset-password":  true,
	"/api/v1/auth/email-register":  true,
	"/api/v1/auth/email-login":     true,
	"/api/v1/auth/send-email-code": true,
	"/api/v1/auth/refresh":         true,
	"/api/v1/timezones":            true,
}

var publicPrefixes = []string{
	"/uploads/",
	"/firmware/",
	"/ws/",
	"/api/v1/captcha/",
}

var exactUntrustedIdentityHeaders = map[string]struct{}{
	"x-organization-id":       {},
	"x-tenant-id":             {},
	"x-membership-id":         {},
	"x-membership-version":    {},
	"x-session-version":       {},
	"x-session-id":            {},
	"x-authorization-version": {},
	"x-token-jti":             {},
	"x-token-issued-at":       {},
}

func isPublicPath(path string) bool {
	if publicPaths[path] {
		return true
	}
	for _, prefix := range publicPrefixes {
		if strings.HasPrefix(path, prefix) {
			return true
		}
	}
	return false
}

// StripUntrustedIdentityHeaders must be registered globally so public routes
// cannot forward caller-supplied identity assertions. JWTAuth repeats the
// cleanup as defense in depth before injecting verified values.
func StripUntrustedIdentityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		stripUntrustedIdentityHeaders(c.Request.Header)
		c.Next()
	}
}

func stripUntrustedIdentityHeaders(headers http.Header) {
	for name := range headers {
		lowerName := strings.ToLower(name)
		if strings.HasPrefix(lowerName, "x-user-") {
			headers.Del(name)
			continue
		}
		if _, untrusted := exactUntrustedIdentityHeaders[lowerName]; untrusted {
			headers.Del(name)
		}
	}
}

// JWTAuth keeps the existing call shape while applying the production access
// token profile. Deployments needing different names use JWTAuthWithConfig.
func JWTAuth(secret string) gin.HandlerFunc {
	return JWTAuthWithConfig(JWTAuthConfig{
		Secret:   secret,
		Issuer:   DefaultJWTIssuer,
		Audience: DefaultAccessAudience,
	})
}

func JWTAuthWithConfig(config JWTAuthConfig) gin.HandlerFunc {
	return func(c *gin.Context) {
		stripUntrustedIdentityHeaders(c.Request.Header)

		if isPublicPath(c.Request.URL.Path) {
			c.Next()
			return
		}

		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"code": 401, "message": "missing Authorization header"})
			c.Abort()
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			c.JSON(http.StatusUnauthorized, gin.H{"code": 401, "message": "Authorization must use Bearer token"})
			c.Abort()
			return
		}

		tokenString := strings.TrimSpace(parts[1])
		if tokenString == "" || strings.TrimSpace(config.Secret) == "" ||
			strings.TrimSpace(config.Issuer) == "" || strings.TrimSpace(config.Audience) == "" {
			abortInvalidToken(c)
			return
		}

		claims := &AccessTokenClaims{}
		token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
			if token.Method != jwt.SigningMethodHS256 {
				return nil, fmt.Errorf("unsupported signing algorithm: %v", token.Header["alg"])
			}
			return []byte(config.Secret), nil
		},
			jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
			jwt.WithIssuer(config.Issuer),
			jwt.WithAudience(config.Audience),
			jwt.WithExpirationRequired(),
			jwt.WithIssuedAt(),
			jwt.WithLeeway(config.Leeway),
		)

		if err != nil || !token.Valid || !validAccessTokenClaims(claims, config) {
			abortInvalidToken(c)
			return
		}

		injectTrustedIdentityHeaders(c.Request.Header, claims)
		c.Next()
	}
}

func validAccessTokenClaims(claims *AccessTokenClaims, config JWTAuthConfig) bool {
	if claims.TokenVersion != currentJWTTokenVersion || claims.TokenType != "access" {
		return false
	}
	if claims.UserID <= 0 || claims.RootTenantID <= 0 || claims.OrganizationID <= 0 ||
		claims.MembershipID <= 0 || claims.MembershipVersion <= 0 ||
		claims.SessionVersion <= 0 || claims.AuthorizationVersion <= 0 {
		return false
	}
	if claims.Role == nil || *claims.Role < 0 || *claims.Role > 5 {
		return false
	}
	if strings.TrimSpace(claims.SessionID) == "" {
		return false
	}
	if claims.Subject != strconv.FormatInt(claims.UserID, 10) || strings.TrimSpace(claims.ID) == "" {
		return false
	}
	if claims.Issuer != config.Issuer || len(claims.Audience) != 1 || claims.Audience[0] != config.Audience {
		return false
	}
	return claims.ExpiresAt != nil && claims.IssuedAt != nil && claims.NotBefore != nil
}

func injectTrustedIdentityHeaders(headers http.Header, claims *AccessTokenClaims) {
	stripUntrustedIdentityHeaders(headers)
	headers.Set("X-User-ID", strconv.FormatInt(claims.UserID, 10))
	headers.Set("X-User-Sub", claims.Subject)
	headers.Set("X-Tenant-ID", strconv.FormatInt(claims.RootTenantID, 10))
	headers.Set("X-Organization-ID", strconv.FormatInt(claims.OrganizationID, 10))
	headers.Set("X-Membership-ID", strconv.FormatInt(claims.MembershipID, 10))
	headers.Set("X-Membership-Version", strconv.FormatInt(claims.MembershipVersion, 10))
	headers.Set("X-Session-Version", strconv.FormatInt(claims.SessionVersion, 10))
	headers.Set("X-Session-ID", claims.SessionID)
	headers.Set("X-Authorization-Version", strconv.FormatInt(claims.AuthorizationVersion, 10))
	headers.Set("X-Token-JTI", claims.ID)
	headers.Set("X-Token-Issued-At", strconv.FormatInt(claims.IssuedAt.Time.UnixMilli(), 10))
	if claims.Phone != "" {
		headers.Set("X-User-Phone", claims.Phone)
	}
	if claims.Role != nil {
		headers.Set("X-User-Role", strconv.Itoa(*claims.Role))
	}
}

func abortInvalidToken(c *gin.Context) {
	c.JSON(http.StatusUnauthorized, gin.H{"code": 401, "message": "invalid token"})
	c.Abort()
}
