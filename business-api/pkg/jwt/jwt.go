package jwt

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"strconv"
	"time"

	jwtlib "github.com/golang-jwt/jwt/v5"
)

const (
	TokenTypeAccess  = "access"
	TokenTypeRefresh = "refresh"

	DefaultAccessAudience  = "inv-platform-api"
	DefaultRefreshAudience = "inv-platform-auth"
)

// AccessClaims binds an access token to one active organization membership.
// Phone and Role are retained only for the legacy GenerateToken/ParseToken
// compatibility path; authorization must use the organization context fields.
type AccessClaims struct {
	TokenVersion         int64  `json:"token_version"`
	UserID               int64  `json:"user_id"`
	RootTenantID         int64  `json:"root_tenant_id,omitempty"`
	OrganizationID       int64  `json:"organization_id,omitempty"`
	MembershipID         int64  `json:"membership_id,omitempty"`
	MembershipVersion    int64  `json:"membership_version,omitempty"`
	AuthorizationVersion int64  `json:"authorization_version,omitempty"`
	SessionVersion       int64  `json:"session_version,omitempty"`
	SessionID            string `json:"session_id,omitempty"`
	TokenType            string `json:"token_type"`
	Phone                string `json:"phone,omitempty"`
	Role                 *int   `json:"role,omitempty"` // Pointer type to distinguish unset vs role=0
	jwtlib.RegisteredClaims
}

// Claims preserves the old public API while making its parser access-only.
type Claims = AccessClaims

// RefreshClaims deliberately contains no organization, role, or permission
// context. A refresh session must resolve the current context server-side.
type RefreshClaims struct {
	TokenVersion   int64  `json:"token_version"`
	UserID         int64  `json:"user_id"`
	SessionVersion int64  `json:"session_version"`
	SessionID      string `json:"session_id"`
	TokenType      string `json:"token_type"`
	jwtlib.RegisteredClaims
}

type JWTConfig struct {
	Secret            string
	ExpireTime        time.Duration
	RefreshExpireTime time.Duration
	Issuer            string
	AccessAudience    string
	RefreshAudience   string
}

type JWT struct {
	config *JWTConfig
}

func NewJWT(config *JWTConfig) *JWT {
	copy := *config
	if copy.AccessAudience == "" {
		copy.AccessAudience = DefaultAccessAudience
	}
	if copy.RefreshAudience == "" {
		copy.RefreshAudience = DefaultRefreshAudience
	}
	return &JWT{config: &copy}
}

// GenerateToken is the legacy, context-free login token pair generator.
// Its access token is accepted only by ParseToken; ParseAccessToken rejects it
// because it is not bound to an organization membership.
func (j *JWT) GenerateToken(userID int64, phone string, role *int) (string, string, error) {
	return j.GenerateTokenWithSessionVersion(userID, phone, role, 1)
}

func (j *JWT) GenerateTokenWithSessionVersion(userID int64, phone string, role *int, sessionVersion int64) (string, string, error) {
	if sessionVersion <= 0 {
		return "", "", errors.New("invalid session version")
	}
	accessJTI, err := generateJTI()
	if err != nil {
		return "", "", err
	}
	now := time.Now().UTC()
	claims := AccessClaims{
		TokenVersion: 2, UserID: userID, Phone: phone, TokenType: TokenTypeAccess,
		RegisteredClaims: j.registeredClaims(now, j.config.ExpireTime, j.config.AccessAudience, accessJTI, userID),
	}
	if role != nil {
		claims.Role = role
	}
	accessToken, err := j.sign(claims)
	if err != nil {
		return "", "", err
	}
	refreshToken, err := j.GenerateRefreshTokenWithVersion(userID, sessionVersion)
	if err != nil {
		return "", "", err
	}
	return accessToken, refreshToken, nil
}

func (j *JWT) GenerateContextAccessToken(userID, rootTenantID, organizationID, membershipID, membershipVersion, authorizationVersion, sessionVersion int64) (string, error) {
	return j.GenerateContextAccessTokenWithLegacy(userID, rootTenantID, organizationID, membershipID, membershipVersion, authorizationVersion, sessionVersion, "", ptrInt(0))
}

func (j *JWT) GenerateContextAccessTokenWithLegacy(userID, rootTenantID, organizationID, membershipID, membershipVersion, authorizationVersion, sessionVersion int64, phone string, role *int) (string, error) {
	sessionID, err := generateJTI()
	if err != nil {
		return "", err
	}
	return j.GenerateContextAccessTokenForSession(userID, rootTenantID, organizationID, membershipID, membershipVersion, authorizationVersion, sessionVersion, sessionID, phone, role)
}

func (j *JWT) GenerateContextAccessTokenForSession(userID, rootTenantID, organizationID, membershipID, membershipVersion, authorizationVersion, sessionVersion int64, sessionID, phone string, role *int) (string, error) {
	if userID <= 0 || rootTenantID <= 0 || organizationID <= 0 || membershipID <= 0 || membershipVersion <= 0 || authorizationVersion <= 0 || sessionVersion <= 0 {
		return "", errors.New("invalid access token context")
	}
	if sessionID == "" {
		return "", errors.New("invalid access token session")
	}
	jti, err := generateJTI()
	if err != nil {
		return "", err
	}
	now := time.Now().UTC()
	claims := AccessClaims{
		TokenVersion: 2,
		UserID:       userID, RootTenantID: rootTenantID, OrganizationID: organizationID,
		MembershipID: membershipID, MembershipVersion: membershipVersion,
		AuthorizationVersion: authorizationVersion, SessionVersion: sessionVersion,
		SessionID: sessionID, TokenType: TokenTypeAccess, Phone: phone,
		RegisteredClaims: j.registeredClaims(now, j.config.ExpireTime, j.config.AccessAudience, jti, userID),
	}
	if role != nil {
		claims.Role = role
	}
	return j.sign(claims)
}

// GenerateRefreshToken keeps the legacy parameters for source compatibility.
// Phone and role are intentionally not embedded in the refresh token.
func (j *JWT) GenerateRefreshToken(userID int64, _ string, _ int) (string, error) {
	return j.GenerateRefreshTokenWithVersion(userID, 1)
}

func (j *JWT) GenerateRefreshTokenWithVersion(userID, sessionVersion int64) (string, error) {
	return j.GenerateRefreshTokenForSession(userID, sessionVersion, "")
}

func (j *JWT) GenerateRefreshTokenForSession(userID, sessionVersion int64, sessionID string) (string, error) {
	if userID <= 0 || sessionVersion <= 0 {
		return "", errors.New("invalid refresh token user")
	}
	jti, err := generateJTI()
	if err != nil {
		return "", err
	}
	if sessionID == "" {
		sessionID, err = generateJTI()
		if err != nil {
			return "", err
		}
	}
	now := time.Now().UTC()
	claims := RefreshClaims{
		TokenVersion: 2, UserID: userID, SessionVersion: sessionVersion, SessionID: sessionID, TokenType: TokenTypeRefresh,
		RegisteredClaims: j.registeredClaims(now, j.config.RefreshExpireTime, j.config.RefreshAudience, jti, userID),
	}
	return j.sign(claims)
}

func (j *JWT) registeredClaims(now time.Time, lifetime time.Duration, audience, jti string, userID int64) jwtlib.RegisteredClaims {
	return jwtlib.RegisteredClaims{
		Subject: strconv.FormatInt(userID, 10), Issuer: j.config.Issuer,
		Audience: jwtlib.ClaimStrings{audience}, ID: jti,
		ExpiresAt: jwtlib.NewNumericDate(now.Add(lifetime)), IssuedAt: jwtlib.NewNumericDate(now),
		NotBefore: jwtlib.NewNumericDate(now),
	}
}

// ptrInt returns a pointer to an int value.
// Used to create *int for JWT claims with nullable role field.
func ptrInt(i int) *int {
	return &i
}

// PtrInt exports the ptrInt helper function for use outside the package.
func PtrInt(i int) *int {
	return ptrInt(i)
}

func (j *JWT) sign(claims jwtlib.Claims) (string, error) {
	return jwtlib.NewWithClaims(jwtlib.SigningMethodHS256, claims).SignedString([]byte(j.config.Secret))
}

func generateJTI() (string, error) {
	bytes := make([]byte, 16)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}

// ParseToken is the legacy compatibility parser. It accepts only access tokens
// issued for the API audience, but does not require an organization context.
func (j *JWT) ParseToken(tokenString string) (*Claims, error) {
	return j.parseAccessToken(tokenString, false)
}

func (j *JWT) ParseAccessToken(tokenString string) (*AccessClaims, error) {
	return j.parseAccessToken(tokenString, true)
}

func (j *JWT) parseAccessToken(tokenString string, requireContext bool) (*AccessClaims, error) {
	claims := &AccessClaims{}
	if err := j.parse(tokenString, claims, j.config.AccessAudience); err != nil {
		return nil, err
	}
	if err := validateRegisteredClaims(claims.RegisteredClaims, claims.UserID, TokenTypeAccess, claims.TokenType); err != nil {
		return nil, err
	}
	if claims.TokenVersion != 2 {
		return nil, errors.New("unsupported access token version")
	}
	// Validate role only if it's set (not nil)
	if claims.Role != nil && (*claims.Role < 0 || *claims.Role > 5) {
		return nil, errors.New("access token contains invalid legacy context")
	}
	if requireContext && (claims.RootTenantID <= 0 || claims.OrganizationID <= 0 || claims.MembershipID <= 0 ||
		claims.MembershipVersion <= 0 || claims.AuthorizationVersion <= 0 || claims.SessionVersion <= 0 || claims.SessionID == "") {
		return nil, errors.New("access token missing authorization context")
	}
	return claims, nil
}

func (j *JWT) ParseRefreshToken(tokenString string) (*RefreshClaims, error) {
	claims := &RefreshClaims{}
	if err := j.parse(tokenString, claims, j.config.RefreshAudience); err != nil {
		return nil, err
	}
	if err := validateRegisteredClaims(claims.RegisteredClaims, claims.UserID, TokenTypeRefresh, claims.TokenType); err != nil {
		return nil, err
	}
	if claims.TokenVersion != 2 {
		return nil, errors.New("unsupported refresh token version")
	}
	if claims.SessionVersion <= 0 || claims.SessionID == "" {
		return nil, errors.New("refresh token missing session version")
	}
	return claims, nil
}

func (j *JWT) parse(tokenString string, claims jwtlib.Claims, audience string) error {
	if tokenString == "" {
		return errors.New("empty token")
	}
	token, err := jwtlib.ParseWithClaims(tokenString, claims, func(token *jwtlib.Token) (interface{}, error) {
		if token.Method != jwtlib.SigningMethodHS256 {
			return nil, fmt.Errorf("unexpected signing method: %s", token.Method.Alg())
		}
		return []byte(j.config.Secret), nil
	}, jwtlib.WithValidMethods([]string{jwtlib.SigningMethodHS256.Alg()}), jwtlib.WithIssuer(j.config.Issuer),
		jwtlib.WithAudience(audience), jwtlib.WithExpirationRequired(), jwtlib.WithIssuedAt())
	if err != nil {
		return err
	}
	if !token.Valid {
		return errors.New("invalid token")
	}
	return nil
}

func validateRegisteredClaims(registered jwtlib.RegisteredClaims, userID int64, expectedType, actualType string) error {
	if userID <= 0 || actualType != expectedType || registered.ID == "" || registered.Subject != strconv.FormatInt(userID, 10) ||
		registered.IssuedAt == nil || registered.NotBefore == nil || registered.ExpiresAt == nil || len(registered.Audience) == 0 {
		return errors.New("token missing required claims")
	}
	return nil
}

// RefreshToken is retained for compatibility with callers that used an access
// token to mint another legacy access token. Refresh tokens are never accepted.
func (j *JWT) RefreshToken(tokenString string) (string, error) {
	claims, err := j.ParseToken(tokenString)
	if err != nil {
		return "", err
	}
	var rolePtr *int
	if claims.Role != nil {
		rolePtr = claims.Role
	}
	newToken, _, err := j.GenerateToken(claims.UserID, claims.Phone, rolePtr)
	return newToken, err
}

func (j *JWT) GetJTI(claims *Claims) string {
	if claims == nil {
		return ""
	}
	return claims.ID
}
