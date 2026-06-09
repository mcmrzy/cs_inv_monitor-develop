package handler

import (
	"context"
	"regexp"
	"strings"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
	"golang.org/x/crypto/bcrypt"
)

type AuthHandler struct {
	userService  *service.UserService
	jwtService   *service.JWTService
	smsService   *service.SMSService
	emailService *service.EmailService
	rbacCache    *service.RBACCacheService
}

func NewAuthHandler(userService *service.UserService, jwtService *service.JWTService, smsService *service.SMSService, emailService *service.EmailService, rbacCache *service.RBACCacheService) *AuthHandler {
	return &AuthHandler{
		userService:  userService,
		jwtService:   jwtService,
		smsService:   smsService,
		emailService: emailService,
		rbacCache:    rbacCache,
	}
}

type LoginRequest struct {
	Account  string `json:"account" binding:"required"`
	Password string `json:"password" binding:"required"`
}

type LoginResponse struct {
	AccessToken  string      `json:"access_token"`
	RefreshToken string      `json:"refresh_token"`
	User         *model.User `json:"user"`
	ExpiresIn    int64       `json:"expires_in"`
	Permissions  []string    `json:"permissions"`
}

func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	var user *model.User

	user, _ = h.userService.GetByPhone(c.Request.Context(), req.Account)

	if user == nil {
		user, _ = h.userService.GetByEmail(c.Request.Context(), req.Account)
	}

	if user == nil {
		user, _ = h.userService.GetByNickname(c.Request.Context(), req.Account)
	}

	if user == nil {
		response.Error(c, 4001, "user not found")
		return
	}

	if user.Status != 1 {
		response.Error(c, 4002, "account disabled")
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		response.Error(c, 4003, "invalid password")
		return
	}

	token, refreshToken, err := h.jwtService.GenerateToken(user.ID, user.Phone, user.Role)
	if err != nil {
		response.InternalError(c, "generate token failed")
		return
	}

	if err := h.jwtService.StoreRefreshToken(c.Request.Context(), user.ID, refreshToken, 7*24*time.Hour); err != nil {
		logger.Warn("Failed to store refresh token", zap.Error(err))
	}

	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := h.userService.UpdateLoginInfo(ctx, user.ID, c.ClientIP()); err != nil {
			logger.Warn("UpdateLoginInfo failed", zap.Error(err))
		}
	}()
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		h.rbacCache.CacheUserPermissions(ctx, user.ID)
	}()

	// 获取用户权限列表
	permissions, _ := h.rbacCache.GetUserPermissions(c.Request.Context(), user.ID)

	user.PasswordHash = ""
	response.Success(c, LoginResponse{
		AccessToken:  token,
		RefreshToken: refreshToken,
		User:         user,
		ExpiresIn:    7200,
		Permissions:  permissions,
	})
}

type RegisterRequest struct {
	Phone    string `json:"phone" binding:"required"`
	Code     string `json:"code" binding:"required"`
	Password string `json:"password" binding:"required,min=6,max=20"`
}

func (h *AuthHandler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	existingUser, err := h.userService.GetByPhone(c.Request.Context(), req.Phone)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	if existingUser != nil {
		response.Error(c, 4004, "phone already registered")
		return
	}

	if !h.smsService.VerifyCode(c.Request.Context(), req.Phone, req.Code, "register") {
		response.Error(c, 4005, "invalid verification code")
		return
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		response.InternalError(c, "password encryption failed")
		return
	}

	user := &model.User{
		Phone:        req.Phone,
		PasswordHash: string(hashedPassword),
		Role:         3,
		Status:       1,
	}

	if err := h.userService.Create(c.Request.Context(), user); err != nil {
		response.InternalError(c, "create user failed")
		return
	}

	token, refreshToken, err := h.jwtService.GenerateToken(user.ID, user.Phone, user.Role)
	if err != nil {
		response.InternalError(c, "generate token failed")
		return
	}

	if err := h.jwtService.StoreRefreshToken(c.Request.Context(), user.ID, refreshToken, 7*24*time.Hour); err != nil {
		logger.Warn("Failed to store refresh token", zap.Error(err))
	}

	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := h.userService.UpdateLoginInfo(ctx, user.ID, c.ClientIP()); err != nil {
			logger.Warn("UpdateLoginInfo failed", zap.Error(err))
		}
	}()
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		h.rbacCache.CacheUserPermissions(ctx, user.ID)
	}()

	user.PasswordHash = ""
	response.Success(c, LoginResponse{
		AccessToken:  token,
		RefreshToken: refreshToken,
		User:         user,
		ExpiresIn:    7200,
	})
}

type SendCodeRequest struct {
	Phone string `json:"phone" binding:"required"`
	Type  string `json:"type" binding:"required"`
}

func (h *AuthHandler) SendCode(c *gin.Context) {
	var req SendCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	if err := h.smsService.SendCode(c.Request.Context(), req.Phone, req.Type); err != nil {
		response.Error(c, 4006, "send code failed: "+err.Error())
		return
	}

	response.SuccessWithMessage(c, "code sent", nil)
}

type ResetPasswordRequest struct {
	Phone       string `json:"phone" binding:"required"`
	Code        string `json:"code" binding:"required"`
	NewPassword string `json:"new_password" binding:"required,min=6,max=20"`
}

func (h *AuthHandler) ResetPassword(c *gin.Context) {
	var req ResetPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	user, err := h.userService.GetByPhone(c.Request.Context(), req.Phone)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	if user == nil {
		response.Error(c, 4001, "user not found")
		return
	}

	if !h.smsService.VerifyCode(c.Request.Context(), req.Phone, req.Code, "reset_password") {
		response.Error(c, 4005, "invalid verification code")
		return
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		response.InternalError(c, "password encryption failed")
		return
	}

	if err := h.userService.UpdatePassword(c.Request.Context(), user.ID, string(hashedPassword)); err != nil {
		response.InternalError(c, "update password failed")
		return
	}

	response.SuccessWithMessage(c, "password reset success", nil)
}

type ChangePasswordRequest struct {
	OldPassword string `json:"old_password" binding:"required"`
	NewPassword string `json:"new_password" binding:"required,min=6,max=20"`
}

func (h *AuthHandler) ChangePassword(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req ChangePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	user, err := h.userService.GetByID(c.Request.Context(), userID)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.OldPassword)); err != nil {
		response.Error(c, 4007, "old password incorrect")
		return
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		response.InternalError(c, "password encryption failed")
		return
	}

	if err := h.userService.UpdatePassword(c.Request.Context(), userID, string(hashedPassword)); err != nil {
		response.InternalError(c, "update password failed")
		return
	}

	response.SuccessWithMessage(c, "password changed success", nil)
}

func (h *AuthHandler) GetProfile(c *gin.Context) {
	userID := middleware.GetUserID(c)

	user, err := h.userService.GetByID(c.Request.Context(), userID)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	if user == nil {
		response.NotFound(c, "user not found")
		return
	}

	user.PasswordHash = ""
	response.Success(c, user)
}

type UpdateProfileRequest struct {
	Nickname string `json:"nickname"`
	Avatar   string `json:"avatar"`
}

func (h *AuthHandler) UpdateProfile(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req UpdateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	if err := h.userService.UpdateProfile(c.Request.Context(), userID, req.Nickname, req.Avatar); err != nil {
		response.InternalError(c, "update profile failed")
		return
	}

	response.SuccessWithMessage(c, "profile updated", nil)
}

func (h *AuthHandler) Logout(c *gin.Context) {
	userID := middleware.GetUserID(c)

	authHeader := c.GetHeader("Authorization")
	if authHeader != "" {
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) == 2 && parts[0] == "Bearer" {
			if claims, err := h.jwtService.ParseToken(parts[1]); err == nil {
				jti := h.jwtService.GetJTI(claims)
				if jti != "" {
					h.jwtService.AddToBlacklist(c.Request.Context(), jti, 2*time.Hour)
				}
			}
		}
	}

	if refreshToken := c.GetHeader("X-Refresh-Token"); refreshToken != "" && userID > 0 {
		h.jwtService.RevokeRefreshToken(c.Request.Context(), userID, refreshToken)
	}

	response.SuccessWithMessage(c, "logout success", nil)
}

type RefreshTokenRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

func (h *AuthHandler) RefreshToken(c *gin.Context) {
	var req RefreshTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	claims, err := h.jwtService.ParseToken(req.RefreshToken)
	if err != nil {
		response.Unauthorized(c, "invalid refresh token")
		return
	}

	if !h.jwtService.ValidateRefreshToken(c.Request.Context(), claims.UserID, req.RefreshToken) {
		response.Unauthorized(c, "refresh token expired or revoked")
		return
	}

	newAccessToken, newRefreshToken, err := h.jwtService.GenerateToken(claims.UserID, claims.Phone, claims.Role)
	if err != nil {
		response.InternalError(c, "generate token failed")
		return
	}

	h.jwtService.RevokeRefreshToken(c.Request.Context(), claims.UserID, req.RefreshToken)
	h.jwtService.StoreRefreshToken(c.Request.Context(), claims.UserID, newRefreshToken, 7*24*time.Hour)

	response.Success(c, gin.H{
		"access_token":  newAccessToken,
		"refresh_token": newRefreshToken,
		"expires_in":    7200,
	})
}

var emailRegex = regexp.MustCompile(`^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$`)

type SendEmailCodeRequest struct {
	Email string `json:"email" binding:"required"`
	Type  string `json:"type" binding:"required"`
}

func (h *AuthHandler) SendEmailCode(c *gin.Context) {
	var req SendEmailCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	if !emailRegex.MatchString(req.Email) {
		response.Error(c, 4008, "invalid email format")
		return
	}

	if err := h.emailService.SendCode(c.Request.Context(), req.Email, req.Type); err != nil {
		response.Error(c, 4010, "send email code failed: "+err.Error())
		return
	}

	response.SuccessWithMessage(c, "code sent", nil)
}

type EmailRegisterRequest struct {
	Email    string `json:"email" binding:"required"`
	Password string `json:"password" binding:"required,min=6,max=20"`
	Code     string `json:"code" binding:"required"`
	Phone    string `json:"phone" binding:"required"`
	Nickname string `json:"nickname" binding:"required"`
}

func (h *AuthHandler) EmailRegister(c *gin.Context) {
	var req EmailRegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	if !emailRegex.MatchString(req.Email) {
		response.Error(c, 4008, "invalid email format")
		return
	}

	if len(req.Phone) < 5 {
		response.Error(c, 4010, "invalid phone number")
		return
	}

	if !h.emailService.VerifyCode(c.Request.Context(), req.Email, req.Code, "register") {
		response.Error(c, 4005, "invalid verification code")
		return
	}

	existingEmail, _ := h.userService.GetByEmail(c.Request.Context(), req.Email)
	if existingEmail != nil {
		response.Error(c, 4009, "email already registered")
		return
	}

	existingPhone, _ := h.userService.GetByPhone(c.Request.Context(), req.Phone)
	if existingPhone != nil {
		response.Error(c, 4004, "phone already registered")
		return
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		response.InternalError(c, "password encryption failed")
		return
	}

	user := &model.User{
		Phone:        req.Phone,
		Email:        req.Email,
		PasswordHash: string(hashedPassword),
		Nickname:     req.Nickname,
		Role:         3,
		Status:       1,
	}

	if err := h.userService.Create(c.Request.Context(), user); err != nil {
		response.InternalError(c, "create user failed: "+err.Error())
		return
	}

	token, refreshToken, err := h.jwtService.GenerateToken(user.ID, user.Phone, user.Role)
	if err != nil {
		response.InternalError(c, "generate token failed")
		return
	}

	if err := h.jwtService.StoreRefreshToken(c.Request.Context(), user.ID, refreshToken, 7*24*time.Hour); err != nil {
		logger.Warn("Failed to store refresh token", zap.Error(err))
	}

	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := h.userService.UpdateLoginInfo(ctx, user.ID, c.ClientIP()); err != nil {
			logger.Warn("UpdateLoginInfo failed", zap.Error(err))
		}
	}()
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		h.rbacCache.CacheUserPermissions(ctx, user.ID)
	}()

	user.PasswordHash = ""
	response.Success(c, LoginResponse{
		AccessToken:  token,
		RefreshToken: refreshToken,
		User:         user,
		ExpiresIn:    7200,
	})
}

type EmailLoginRequest struct {
	Email    string `json:"email" binding:"required"`
	Password string `json:"password" binding:"required"`
}

func (h *AuthHandler) EmailLogin(c *gin.Context) {
	var req EmailLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	user, err := h.userService.GetByEmail(c.Request.Context(), req.Email)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	if user == nil {
		response.Error(c, 4001, "user not found")
		return
	}

	if user.Status != 1 {
		response.Error(c, 4002, "account disabled")
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		response.Error(c, 4003, "invalid password")
		return
	}

	identifier := user.Phone
	if identifier == "" {
		identifier = user.Email
	}
	token, refreshToken, err := h.jwtService.GenerateToken(user.ID, identifier, user.Role)
	if err != nil {
		response.InternalError(c, "generate token failed")
		return
	}

	if err := h.jwtService.StoreRefreshToken(c.Request.Context(), user.ID, refreshToken, 7*24*time.Hour); err != nil {
		logger.Warn("Failed to store refresh token", zap.Error(err))
	}

	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := h.userService.UpdateLoginInfo(ctx, user.ID, c.ClientIP()); err != nil {
			logger.Warn("UpdateLoginInfo failed", zap.Error(err))
		}
	}()
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		h.rbacCache.CacheUserPermissions(ctx, user.ID)
	}()

	user.PasswordHash = ""
	response.Success(c, LoginResponse{
		AccessToken:  token,
		RefreshToken: refreshToken,
		User:         user,
		ExpiresIn:    7200,
	})
}