package jwt

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

type Claims struct {
	UserID     int64  `json:"user_id"`
	Phone      string `json:"phone"`
	Role       int    `json:"role"`
	TokenType  string `json:"token_type"`
	SessionIAT int64  `json:"session_iat_ms"`
	jwt.RegisteredClaims
}

const (
	TokenTypeAccess  = "access"
	TokenTypeRefresh = "refresh"
)

type JWTConfig struct {
	Secret            string
	ExpireTime        time.Duration
	RefreshExpireTime time.Duration
	Issuer            string
}

type JWT struct {
	config *JWTConfig
}

func NewJWT(config *JWTConfig) *JWT {
	return &JWT{config: config}
}

func (j *JWT) GenerateToken(userID int64, phone string, role int) (string, string, error) {
	now := time.Now().UTC()
	jti, err := generateJTI()
	if err != nil {
		return "", "", err
	}

	claims := Claims{
		UserID:     userID,
		Phone:      phone,
		Role:       role,
		TokenType:  TokenTypeAccess,
		SessionIAT: now.UnixMilli(),
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(now.Add(j.config.ExpireTime)),
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now),
			Issuer:    j.config.Issuer,
			ID:        jti,
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString([]byte(j.config.Secret))
	if err != nil {
		return "", "", err
	}

	refreshToken, err := j.generateRefreshToken(userID, phone, role)
	if err != nil {
		return "", "", err
	}

	return signed, refreshToken, nil
}

func (j *JWT) generateRefreshToken(userID int64, phone string, role int) (string, error) {
	now := time.Now().UTC()
	jti, err := generateJTI()
	if err != nil {
		return "", err
	}

	claims := Claims{
		UserID:     userID,
		Phone:      phone,
		Role:       role,
		TokenType:  TokenTypeRefresh,
		SessionIAT: now.UnixMilli(),
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(now.Add(j.config.RefreshExpireTime)),
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now),
			Issuer:    j.config.Issuer,
			ID:        jti,
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(j.config.Secret))
}

func generateJTI() (string, error) {
	bytes := make([]byte, 16)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}

func (j *JWT) GenerateRefreshToken(userID int64, phone string, role int) (string, error) {
	return j.generateRefreshToken(userID, phone, role)
}

func (j *JWT) ParseAccessToken(tokenString string) (*Claims, error) {
	claims, err := j.ParseToken(tokenString)
	if err != nil {
		return nil, err
	}
	if claims.TokenType != TokenTypeAccess || claims.ID == "" || claims.SessionIAT <= 0 || claims.UserID <= 0 || claims.Role < 0 || claims.Role > 5 {
		return nil, errors.New("token is not an access token")
	}
	return claims, nil
}

func (j *JWT) ParseRefreshToken(tokenString string) (*Claims, error) {
	claims, err := j.ParseToken(tokenString)
	if err != nil {
		return nil, err
	}
	if claims.TokenType != TokenTypeRefresh || claims.ID == "" || claims.SessionIAT <= 0 || claims.UserID <= 0 || claims.Role < 0 || claims.Role > 5 {
		return nil, errors.New("token is not a refresh token")
	}
	return claims, nil
}

func (j *JWT) ParseToken(tokenString string) (*Claims, error) {
	options := []jwt.ParserOption{
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithExpirationRequired(),
	}
	if j.config.Issuer != "" {
		options = append(options, jwt.WithIssuer(j.config.Issuer))
	}
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		return []byte(j.config.Secret), nil
	}, options...)

	if err != nil {
		return nil, err
	}

	if claims, ok := token.Claims.(*Claims); ok && token.Valid {
		return claims, nil
	}

	return nil, errors.New("invalid token")
}

func (j *JWT) RefreshToken(tokenString string) (string, error) {
	claims, err := j.ParseRefreshToken(tokenString)
	if err != nil {
		return "", err
	}

	newToken, _, err := j.GenerateToken(claims.UserID, claims.Phone, claims.Role)
	return newToken, err
}

func (j *JWT) GetJTI(claims *Claims) string {
	if claims == nil {
		return ""
	}
	return claims.ID
}
