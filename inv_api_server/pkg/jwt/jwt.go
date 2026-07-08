package jwt

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

type Claims struct {
	UserID int64  `json:"user_id"`
	Phone  string `json:"phone"`
	Role   int    `json:"role"`
	JTI    string `json:"jti"`
	jwt.RegisteredClaims
}

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
	jti, err := generateJTI()
	if err != nil {
		return "", "", err
	}

	claims := Claims{
		UserID: userID,
		Phone:  phone,
		Role:   role,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().UTC().Add(j.config.ExpireTime)),
			IssuedAt:  jwt.NewNumericDate(time.Now().UTC()),
			NotBefore: jwt.NewNumericDate(time.Now().UTC()),
			Issuer:    j.config.Issuer,
			ID:        jti,
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString([]byte(j.config.Secret))
	if err != nil {
		return "", "", err
	}

	refreshToken, err := j.generateRefreshToken(userID, phone, role, jti)
	if err != nil {
		return "", "", err
	}

	return signed, refreshToken, nil
}

func (j *JWT) generateRefreshToken(userID int64, phone string, role int, accessJTI string) (string, error) {
	jti, err := generateJTI()
	if err != nil {
		return "", err
	}

	claims := Claims{
		UserID: userID,
		Phone:  phone,
		Role:   role,
		JTI:    jti,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().UTC().Add(j.config.RefreshExpireTime)),
			IssuedAt:  jwt.NewNumericDate(time.Now().UTC()),
			NotBefore: jwt.NewNumericDate(time.Now().UTC()),
			Issuer:    j.config.Issuer,
			ID:        accessJTI,
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
	accessJTI, err := generateJTI()
	if err != nil {
		return "", err
	}
	return j.generateRefreshToken(userID, phone, role, accessJTI)
}

func (j *JWT) ParseToken(tokenString string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		return []byte(j.config.Secret), nil
	})

	if err != nil {
		return nil, err
	}

	if claims, ok := token.Claims.(*Claims); ok && token.Valid {
		return claims, nil
	}

	return nil, errors.New("invalid token")
}

func (j *JWT) RefreshToken(tokenString string) (string, error) {
	claims, err := j.ParseToken(tokenString)
	if err != nil {
		return "", err
	}

	newToken, _, err := j.GenerateToken(claims.UserID, claims.Phone, claims.Role)
	return newToken, err
}

func (j *JWT) GetJTI(claims *Claims) string {
	return claims.JTI
}
