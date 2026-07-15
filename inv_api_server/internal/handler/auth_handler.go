package handler

import (
	"context"
	"fmt"
	"os"
	"regexp"
	"strings"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/apperr"
	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"
	"inv-api-server/pkg/timezone"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
	"golang.org/x/crypto/bcrypt"
)

// Self-registered accounts are terminal users. Elevated partner, installer,
// operator, and administrator roles must only be assigned by an authorized
// administrator after registration.
const defaultSelfRegisteredRole = 5

// isProduction 检查是否为生产环境
func isProduction() bool {
	return os.Getenv("GIN_MODE") == "release" || os.Getenv("APP_ENV") == "production"
}

// setAuthCookies 设置 httpOnly cookie 存储 token（防 XSS）
// 生产环境设置 Secure=true，SameSite=Strict
func setAuthCookies(c *gin.Context, accessToken, refreshToken string, accessExpire, refreshExpire time.Duration) {
	secure := isProduction()
	c.SetCookie("access_token", accessToken, int(accessExpire.Seconds()), "/", "", secure, true)
	c.SetCookie("refresh_token", refreshToken, int(refreshExpire.Seconds()), "/", "", secure, true)
}

// clearAuthCookies 清除认证 cookie
func clearAuthCookies(c *gin.Context) {
	secure := isProduction()
	c.SetCookie("access_token", "", -1, "/", "", secure, true)
	c.SetCookie("refresh_token", "", -1, "/", "", secure, true)
}

type AuthHandler struct {
	userService    *service.UserService
	jwtService     *service.JWTService
	smsService     *service.SMSService
	emailService   *service.EmailService
	rbacCache      *service.RBACCacheService
	captchaHandler *CaptchaHandler
}

func NewAuthHandler(userService *service.UserService, jwtService *service.JWTService, smsService *service.SMSService, emailService *service.EmailService, rbacCache *service.RBACCacheService, captchaHandler *CaptchaHandler) *AuthHandler {
	return &AuthHandler{
		userService:    userService,
		jwtService:     jwtService,
		smsService:     smsService,
		emailService:   emailService,
		rbacCache:      rbacCache,
		captchaHandler: captchaHandler,
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

// loadUserPermissions keeps every login and registration response on the same
// RBAC contract.  Return an empty JSON array on an infrastructure error instead
// of silently returning null; the gateway still performs the authoritative
// permission check for every protected request.
func (h *AuthHandler) loadUserPermissions(ctx context.Context, userID int64) []string {
	permissions := make([]string, 0)
	if h.rbacCache == nil {
		return permissions
	}

	loaded, err := h.rbacCache.GetUserPermissions(ctx, userID)
	if err != nil {
		logger.Warn("Failed to load permissions for auth response",
			zap.Int64("user_id", userID), zap.Error(err))
		return permissions
	}
	if loaded == nil {
		return permissions
	}
	return loaded
}

func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	// 检查登录失败次数限制（防暴力破解）
	failKey := fmt.Sprintf("login_fail:%s", req.Account)
	failCount, _ := h.userService.Cache().Get(c.Request.Context(), failKey).Int()
	if failCount >= 5 {
		ttl, _ := h.userService.Cache().TTL(c.Request.Context(), failKey).Result()
		response.Error(c, 4029, fmt.Sprintf("登录失败次数过多，请 %d 分钟后再试", int(ttl.Minutes())+1))
		return
	}

	// 失败次数 >= 3 时需要验证码
	if failCount >= 3 {
		captchaToken := c.GetHeader("X-Captcha-Token")
		if captchaToken == "" || !h.captchaHandler.CheckCaptchaVerified(c) {
			response.Error(c, 4032, "需要验证码验证")
			return
		}
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
		// 记录登录失败次数
		h.userService.Cache().Incr(c.Request.Context(), failKey)
		h.userService.Cache().Expire(c.Request.Context(), failKey, 15*time.Minute)
		response.Error(c, 4003, "invalid password")
		return
	}

	// 登录成功，清除失败记录
	h.userService.Cache().Del(c.Request.Context(), failKey)

	token, refreshToken, err := h.jwtService.GenerateToken(user.ID, user.Phone, user.Role)
	if err != nil {
		response.HandleError(c, apperr.Internal("generate token failed", err))
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
		// 记录登录审计日志
		h.userService.LogAudit(ctx, user.ID, user.Nickname, "login", "auth", "", "{}", c.ClientIP())
	}()
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		h.rbacCache.CacheUserPermissions(ctx, user.ID)
	}()

	// 获取用户权限列表
	permissions := h.loadUserPermissions(c.Request.Context(), user.ID)

	// 设置 httpOnly cookie（同时返回 body 保持兼容）
	setAuthCookies(c, token, refreshToken, 2*time.Hour, 7*24*time.Hour)

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
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	existingUser, err := h.userService.GetByPhone(c.Request.Context(), req.Phone)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
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
		response.HandleError(c, apperr.Internal("password encryption failed", err))
		return
	}

	user := &model.User{
		Phone:        req.Phone,
		PasswordHash: string(hashedPassword),
		Role:         defaultSelfRegisteredRole,
		Status:       1,
	}

	if err := h.userService.Create(c.Request.Context(), user); err != nil {
		response.HandleError(c, apperr.Internal("create user failed", err))
		return
	}

	token, refreshToken, err := h.jwtService.GenerateToken(user.ID, user.Phone, user.Role)
	if err != nil {
		response.HandleError(c, apperr.Internal("generate token failed", err))
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
		// 记录注册审计日志
		h.userService.LogAudit(ctx, user.ID, user.Nickname, "register", "auth", "", "{}", c.ClientIP())
	}()
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		h.rbacCache.CacheUserPermissions(ctx, user.ID)
	}()

	user.PasswordHash = ""
	permissions := h.loadUserPermissions(c.Request.Context(), user.ID)
	response.Success(c, LoginResponse{
		AccessToken:  token,
		RefreshToken: refreshToken,
		User:         user,
		ExpiresIn:    7200,
		Permissions:  permissions,
	})
}

type SendCodeRequest struct {
	Phone string `json:"phone" binding:"required"`
	Type  string `json:"type" binding:"required"`
}

func (h *AuthHandler) SendCode(c *gin.Context) {
	var req SendCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	// 检查滑块验证码（发送验证码时不删除 token，登录时再删除）
	captchaToken := c.GetHeader("X-Captcha-Token")
	if captchaToken == "" || !h.captchaHandler.CheckCaptchaToken(c) {
		response.Error(c, 4032, "请先完成滑块验证")
		return
	}

	// IP 级频率限制：每个 IP 每小时最多发送 10 次验证码
	ipLimitKey := fmt.Sprintf("send_code_ip:%s", c.ClientIP())
	ipCount, _ := h.userService.Cache().Get(c.Request.Context(), ipLimitKey).Int()
	if ipCount >= 10 {
		response.Error(c, 4029, "发送验证码过于频繁，请稍后再试")
		return
	}

	// 检查手机号注册状态
	existingUser, err := h.userService.GetByPhone(c.Request.Context(), req.Phone)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	if req.Type == "reset_password" && existingUser == nil {
		response.Error(c, 4001, "该手机号未注册")
		return
	}

	if req.Type == "register" && existingUser != nil {
		response.Error(c, 4009, "该手机号已注册")
		return
	}

	if err := h.smsService.SendCode(c.Request.Context(), req.Phone, req.Type); err != nil {
		logger.Warn("send code failed", zap.String("phone", req.Phone), zap.Error(err))
		response.Error(c, 4006, err.Error())
		return
	}

	// 增加 IP 发送计数
	h.userService.Cache().Incr(c.Request.Context(), ipLimitKey)
	h.userService.Cache().Expire(c.Request.Context(), ipLimitKey, 1*time.Hour)

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
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	user, err := h.userService.GetByPhone(c.Request.Context(), req.Phone)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	if user == nil {
		response.Error(c, 4001, "user not found")
		return
	}

	if !h.smsService.VerifyCode(c.Request.Context(), req.Phone, req.Code, "reset_password") {
		response.Error(c, 4005, "验证码错误")
		return
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		response.HandleError(c, apperr.Internal("password encryption failed", err))
		return
	}

	if err := h.userService.UpdatePassword(c.Request.Context(), user.ID, string(hashedPassword)); err != nil {
		response.HandleError(c, apperr.Internal("update password failed", err))
		return
	}

	// 记录重置密码审计日志
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		h.userService.LogAudit(ctx, user.ID, user.Nickname, "reset_password", "auth", "", "{}", c.ClientIP())
	}()

	response.SuccessWithMessage(c, "password reset success", nil)
}

type EmailResetPasswordRequest struct {
	Email       string `json:"email" binding:"required"`
	Code        string `json:"code" binding:"required"`
	NewPassword string `json:"new_password" binding:"required,min=6,max=20"`
}

func (h *AuthHandler) EmailResetPassword(c *gin.Context) {
	var req EmailResetPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	if !emailRegex.MatchString(req.Email) {
		response.Error(c, 4008, "invalid email format")
		return
	}

	user, err := h.userService.GetByEmail(c.Request.Context(), req.Email)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	if user == nil {
		response.Error(c, 4001, "该邮箱未注册")
		return
	}

	if !h.emailService.VerifyCode(c.Request.Context(), req.Email, req.Code, "reset_password") {
		response.Error(c, 4005, "验证码错误")
		return
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		response.HandleError(c, apperr.Internal("password encryption failed", err))
		return
	}

	if err := h.userService.UpdatePassword(c.Request.Context(), user.ID, string(hashedPassword)); err != nil {
		response.HandleError(c, apperr.Internal("update password failed", err))
		return
	}

	// 重置密码后，撤销该用户所有已有的 refresh token，强制重新登录
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := h.jwtService.RevokeAllUserTokens(ctx, user.ID); err != nil {
			logger.Warn("RevokeAllUserTokens failed after password reset", zap.Error(err))
		}
		// 记录重置密码审计日志
		h.userService.LogAudit(ctx, user.ID, user.Nickname, "reset_password", "auth", "", "{}", c.ClientIP())
	}()

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
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	user, err := h.userService.GetByID(c.Request.Context(), userID)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.OldPassword)); err != nil {
		response.Error(c, 4007, "old password incorrect")
		return
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		response.HandleError(c, apperr.Internal("password encryption failed", err))
		return
	}

	if err := h.userService.UpdatePassword(c.Request.Context(), userID, string(hashedPassword)); err != nil {
		response.HandleError(c, apperr.Internal("update password failed", err))
		return
	}

	response.SuccessWithMessage(c, "password changed success", nil)
}

func (h *AuthHandler) GetProfile(c *gin.Context) {
	userID := middleware.GetUserID(c)

	user, err := h.userService.GetByID(c.Request.Context(), userID)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	if user == nil {
		response.HandleError(c, apperr.NotFound("user not found"))
		return
	}

	user.PasswordHash = ""
	response.Success(c, user)
}

type UpdateProfileRequest struct {
	Nickname string `json:"nickname"`
	Avatar   string `json:"avatar"`
	Timezone string `json:"timezone"`
}

func (h *AuthHandler) UpdateProfile(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req UpdateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	// 验证时区
	if req.Timezone != "" {
		if err := timezone.ValidateTimezone(req.Timezone); err != nil {
			response.HandleError(c, apperr.BadRequest("invalid timezone: "+req.Timezone))
			return
		}
	}

	if err := h.userService.UpdateProfile(c.Request.Context(), userID, req.Nickname, req.Avatar, req.Timezone); err != nil {
		response.HandleError(c, apperr.Internal("update profile failed", err))
		return
	}

	response.SuccessWithMessage(c, "profile updated", nil)
}

func (h *AuthHandler) Logout(c *gin.Context) {
	userID := middleware.GetUserID(c)

	// 从 header 或 cookie 获取 token
	tokenStr := ""
	authHeader := c.GetHeader("Authorization")
	if authHeader != "" {
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) == 2 && parts[0] == "Bearer" {
			tokenStr = parts[1]
		}
	}
	if tokenStr == "" {
		tokenStr, _ = c.Cookie("access_token")
	}

	if tokenStr != "" {
		if claims, err := h.jwtService.ParseToken(tokenStr); err == nil {
			jti := h.jwtService.GetJTI(claims)
			if jti != "" {
				h.jwtService.AddToBlacklist(c.Request.Context(), jti, 2*time.Hour)
			}
		}
	}

	// 从 header 或 cookie 获取 refresh token
	refreshToken := c.GetHeader("X-Refresh-Token")
	if refreshToken == "" {
		refreshToken, _ = c.Cookie("refresh_token")
	}
	if refreshToken != "" && userID > 0 {
		h.jwtService.RevokeRefreshToken(c.Request.Context(), userID, refreshToken)
	}

	// 清除 httpOnly cookie
	clearAuthCookies(c)

	response.SuccessWithMessage(c, "logout success", nil)
}

type RefreshTokenRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

func (h *AuthHandler) RefreshToken(c *gin.Context) {
	var req RefreshTokenRequest
	// 优先从 body 读取，其次从 cookie 读取
	if err := c.ShouldBindJSON(&req); err != nil || req.RefreshToken == "" {
		req.RefreshToken, _ = c.Cookie("refresh_token")
	}

	if req.RefreshToken == "" {
		response.HandleError(c, apperr.BadRequest("missing refresh token"))
		return
	}

	claims, err := h.jwtService.ParseToken(req.RefreshToken)
	if err != nil {
		response.HandleError(c, apperr.Unauthorized("invalid refresh token"))
		return
	}

	newAccessToken, newRefreshToken, err := h.jwtService.GenerateToken(claims.UserID, claims.Phone, claims.Role)
	if err != nil {
		response.HandleError(c, apperr.Internal("generate token failed", err))
		return
	}

	swapped, err := h.jwtService.SwapRefreshToken(c.Request.Context(), claims.UserID, req.RefreshToken, newRefreshToken, 7*24*time.Hour)
	if err != nil {
		response.HandleError(c, apperr.Internal("token refresh failed", err))
		return
	}

	if !swapped {
		err = h.jwtService.StoreRefreshToken(c.Request.Context(), claims.UserID, newRefreshToken, 7*24*time.Hour)
		if err != nil {
			response.HandleError(c, apperr.Internal("token refresh failed", err))
			return
		}
	}

	// 更新 httpOnly cookie
	setAuthCookies(c, newAccessToken, newRefreshToken, 2*time.Hour, 7*24*time.Hour)

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
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	// 检查滑块验证码（发送验证码时不删除 token，登录时再删除）
	captchaToken := c.GetHeader("X-Captcha-Token")
	if captchaToken == "" || !h.captchaHandler.CheckCaptchaToken(c) {
		response.Error(c, 4032, "请先完成滑块验证")
		return
	}

	// IP 级频率限制：每个 IP 每小时最多发送 10 次验证码
	ipLimitKey := fmt.Sprintf("send_code_ip:%s", c.ClientIP())
	ipCount, _ := h.userService.Cache().Get(c.Request.Context(), ipLimitKey).Int()
	if ipCount >= 10 {
		response.Error(c, 4029, "发送验证码过于频繁，请稍后再试")
		return
	}

	if !emailRegex.MatchString(req.Email) {
		response.Error(c, 4008, "invalid email format")
		return
	}

	// 检查邮箱注册状态
	existingUser, err := h.userService.GetByEmail(c.Request.Context(), req.Email)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	if req.Type == "reset_password" && existingUser == nil {
		response.Error(c, 4011, "该邮箱未注册")
		return
	}

	if req.Type == "register" && existingUser != nil {
		response.Error(c, 4009, "该邮箱已注册")
		return
	}

	if err := h.emailService.SendCode(c.Request.Context(), req.Email, req.Type); err != nil {
		logger.Warn("send email code failed", zap.String("email", req.Email), zap.Error(err))
		response.Error(c, 4010, err.Error())
		return
	}

	// 增加 IP 发送计数
	h.userService.Cache().Incr(c.Request.Context(), ipLimitKey)
	h.userService.Cache().Expire(c.Request.Context(), ipLimitKey, 1*time.Hour)

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
		response.HandleError(c, apperr.BadRequest("invalid request"))
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
		response.HandleError(c, apperr.Internal("password encryption failed", err))
		return
	}

	user := &model.User{
		Phone:        req.Phone,
		Email:        req.Email,
		PasswordHash: string(hashedPassword),
		Nickname:     req.Nickname,
		Role:         defaultSelfRegisteredRole,
		Status:       1,
	}

	if err := h.userService.Create(c.Request.Context(), user); err != nil {
		logger.Error("create user failed", zap.String("email", req.Email), zap.Error(err))
		response.HandleError(c, apperr.Internal("创建用户失败，请稍后重试", err))
		return
	}

	token, refreshToken, err := h.jwtService.GenerateToken(user.ID, user.Phone, user.Role)
	if err != nil {
		response.HandleError(c, apperr.Internal("generate token failed", err))
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
		// 记录登录审计日志
		h.userService.LogAudit(ctx, user.ID, user.Nickname, "login", "auth", "", "{}", c.ClientIP())
	}()
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		h.rbacCache.CacheUserPermissions(ctx, user.ID)
	}()

	user.PasswordHash = ""
	permissions := h.loadUserPermissions(c.Request.Context(), user.ID)
	response.Success(c, LoginResponse{
		AccessToken:  token,
		RefreshToken: refreshToken,
		User:         user,
		ExpiresIn:    7200,
		Permissions:  permissions,
	})
}

type EmailLoginRequest struct {
	Email    string `json:"email" binding:"required"`
	Password string `json:"password" binding:"required"`
}

func (h *AuthHandler) EmailLogin(c *gin.Context) {
	var req EmailLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	// 检查登录失败次数限制（防暴力破解）
	failKey := fmt.Sprintf("login_fail:%s", req.Email)
	failCount, _ := h.userService.Cache().Get(c.Request.Context(), failKey).Int()
	if failCount >= 5 {
		ttl, _ := h.userService.Cache().TTL(c.Request.Context(), failKey).Result()
		response.Error(c, 4029, fmt.Sprintf("登录失败次数过多，请 %d 分钟后再试", int(ttl.Minutes())+1))
		return
	}

	user, err := h.userService.GetByEmail(c.Request.Context(), req.Email)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
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
		// 记录登录失败次数
		h.userService.Cache().Incr(c.Request.Context(), failKey)
		h.userService.Cache().Expire(c.Request.Context(), failKey, 15*time.Minute)
		response.Error(c, 4003, "invalid password")
		return
	}

	// 登录成功，清除失败记录
	h.userService.Cache().Del(c.Request.Context(), failKey)

	identifier := user.Phone
	if identifier == "" {
		identifier = user.Email
	}
	token, refreshToken, err := h.jwtService.GenerateToken(user.ID, identifier, user.Role)
	if err != nil {
		response.HandleError(c, apperr.Internal("generate token failed", err))
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
		// 记录登录审计日志
		h.userService.LogAudit(ctx, user.ID, user.Nickname, "login", "auth", "", "{}", c.ClientIP())
	}()
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		h.rbacCache.CacheUserPermissions(ctx, user.ID)
	}()

	user.PasswordHash = ""
	permissions := h.loadUserPermissions(c.Request.Context(), user.ID)
	response.Success(c, LoginResponse{
		AccessToken:  token,
		RefreshToken: refreshToken,
		User:         user,
		ExpiresIn:    7200,
		Permissions:  permissions,
	})
}

// PhoneCodeLogin 手机号验证码登录
type PhoneCodeLoginRequest struct {
	Phone string `json:"phone" binding:"required"`
	Code  string `json:"code" binding:"required"`
}

func (h *AuthHandler) PhoneCodeLogin(c *gin.Context) {
	var req PhoneCodeLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	// 验证短信验证码
	if !h.smsService.VerifyCode(c.Request.Context(), req.Phone, req.Code, "login") {
		response.Error(c, 4005, "验证码错误或已过期")
		return
	}

	user, err := h.userService.GetByPhone(c.Request.Context(), req.Phone)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	if user == nil {
		response.Error(c, 4001, "该手机号未注册")
		return
	}

	if user.Status != 1 {
		response.Error(c, 4002, "account disabled")
		return
	}

	// 生成 token
	token, refreshToken, err := h.jwtService.GenerateToken(user.ID, user.Phone, user.Role)
	if err != nil {
		response.HandleError(c, apperr.Internal("generate token failed", err))
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
		h.userService.LogAudit(ctx, user.ID, user.Nickname, "login_by_sms", "auth", "", "{}", c.ClientIP())
	}()
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		h.rbacCache.CacheUserPermissions(ctx, user.ID)
	}()

	permissions := h.loadUserPermissions(c.Request.Context(), user.ID)

	setAuthCookies(c, token, refreshToken, 2*time.Hour, 7*24*time.Hour)

	user.PasswordHash = ""
	response.Success(c, LoginResponse{
		AccessToken:  token,
		RefreshToken: refreshToken,
		User:         user,
		ExpiresIn:    7200,
		Permissions:  permissions,
	})
}

// EmailCodeLogin 邮箱验证码登录
type EmailCodeLoginRequest struct {
	Email string `json:"email" binding:"required"`
	Code  string `json:"code" binding:"required"`
}

func (h *AuthHandler) EmailCodeLogin(c *gin.Context) {
	var req EmailCodeLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	if !emailRegex.MatchString(req.Email) {
		response.Error(c, 4008, "invalid email format")
		return
	}

	// 验证邮箱验证码
	if !h.emailService.VerifyCode(c.Request.Context(), req.Email, req.Code, "login") {
		response.Error(c, 4005, "验证码错误或已过期")
		return
	}

	user, err := h.userService.GetByEmail(c.Request.Context(), req.Email)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	if user == nil {
		response.Error(c, 4001, "该邮箱未注册")
		return
	}

	if user.Status != 1 {
		response.Error(c, 4002, "account disabled")
		return
	}

	identifier := user.Email
	if identifier == "" {
		identifier = user.Phone
	}

	token, refreshToken, err := h.jwtService.GenerateToken(user.ID, identifier, user.Role)
	if err != nil {
		response.HandleError(c, apperr.Internal("generate token failed", err))
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
		h.userService.LogAudit(ctx, user.ID, user.Nickname, "login_by_email", "auth", "", "{}", c.ClientIP())
	}()
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		h.rbacCache.CacheUserPermissions(ctx, user.ID)
	}()

	permissions := h.loadUserPermissions(c.Request.Context(), user.ID)

	setAuthCookies(c, token, refreshToken, 2*time.Hour, 7*24*time.Hour)

	user.PasswordHash = ""
	response.Success(c, LoginResponse{
		AccessToken:  token,
		RefreshToken: refreshToken,
		User:         user,
		ExpiresIn:    7200,
		Permissions:  permissions,
	})
}
