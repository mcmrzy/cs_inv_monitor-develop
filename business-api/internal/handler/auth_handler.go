package handler

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"regexp"
	"strings"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/apperr"
	"inv-api-server/pkg/jwt"
	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"
	"inv-api-server/pkg/timezone"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"go.uber.org/zap"
	"golang.org/x/crypto/bcrypt"
)

// Self-registered accounts are terminal users. Elevated partner, installer,
const (
	accessTokenLifetime  = 15 * time.Minute
	refreshTokenLifetime = 7 * 24 * time.Hour
)

// isProduction 检查是否为生产环境
func isProduction() bool {
	return os.Getenv("GIN_MODE") == "release" || os.Getenv("APP_ENV") == "production"
}

// setAuthCookies 设置 httpOnly cookie 存储 token（防 XSS）
// 生产环境设置 Secure=true，SameSite=Strict
func setAuthCookies(c *gin.Context, accessToken, refreshToken string, accessExpire, refreshExpire time.Duration) {
	secure := isProduction()
	c.SetSameSite(http.SameSiteStrictMode)
	c.SetCookie("access_token", accessToken, int(accessExpire.Seconds()), "/", "", secure, true)
	c.SetCookie("refresh_token", refreshToken, int(refreshExpire.Seconds()), "/", "", secure, true)
}

// clearAuthCookies 清除认证 cookie
func clearAuthCookies(c *gin.Context) {
	secure := isProduction()
	c.SetSameSite(http.SameSiteStrictMode)
	c.SetCookie("access_token", "", -1, "/", "", secure, true)
	c.SetCookie("refresh_token", "", -1, "/", "", secure, true)
}

func requireRefreshSwap(swapped bool, err error) error {
	if err != nil {
		return err
	}
	if !swapped {
		return apperr.Unauthorized("refresh token has been used or revoked")
	}
	return nil
}

type AuthHandler struct {
	userService     *service.UserService
	jwtService      *service.JWTService
	smsService      *service.SMSService
	emailService    *service.EmailService
	rbacCache       *service.RBACCache
	captchaHandler  *CaptchaHandler
	jverifyService  *service.JVerifyService
	contextResolver authorizationContextResolver
}

// cacheUserPermissions safely caches user permissions when RBAC cache is enabled.
// cfg.RBAC.Enabled=false 时 rbacCache 为 nil，直接调用会触发空指针崩溃。
func (h *AuthHandler) cacheUserPermissions(ctx context.Context, userID int64) {
	if h.rbacCache == nil {
		return
	}
	_ = h.rbacCache.CacheUserPermissions(ctx, userID)
}

type authorizationContextResolver interface {
	ResolveAuthorizationSessionContext(ctx context.Context, userID, organizationID int64) (model.AuthorizationSessionContext, error)
	ResolveUserSessionVersion(ctx context.Context, userID int64) (int64, error)
	ResolveDefaultSessionContext(ctx context.Context, userID int64) (model.AuthorizationSessionContext, error)
	LoadAllPermissionCodes(ctx context.Context, actor model.ActorContext) ([]string, error)
}

func NewAuthHandler(userService *service.UserService, jwtService *service.JWTService, smsService *service.SMSService, emailService *service.EmailService, rbacCache *service.RBACCache, captchaHandler *CaptchaHandler, jverifyService *service.JVerifyService) *AuthHandler {
	return &AuthHandler{
		userService:    userService,
		jwtService:     jwtService,
		smsService:     smsService,
		emailService:   emailService,
		rbacCache:      rbacCache,
		captchaHandler: captchaHandler,
		jverifyService: jverifyService,
	}
}

func (h *AuthHandler) SetAuthorizationContextResolver(resolver authorizationContextResolver) {
	h.contextResolver = resolver
}

// loginTokenResult holds the tokens and the active organization context
// produced during login / registration.
type loginTokenResult struct {
	AccessToken          string
	RefreshToken         string
	ActiveOrganizationID int64
	RootTenantID         int64
	MembershipID         int64
}

func (h *AuthHandler) generateLoginTokenPair(ctx context.Context, user *model.User) (loginTokenResult, error) {
	if h.contextResolver == nil {
		return loginTokenResult{}, fmt.Errorf("authorization context resolver unavailable")
	}

	// Try to resolve the user's first active organization membership.
	resolved, err := h.contextResolver.ResolveDefaultSessionContext(ctx, user.ID)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return loginTokenResult{}, fmt.Errorf("resolve default session context: %w", err)
	}

	// When the user has no active membership (super-admin without org,
	// freshly-registered account, etc.) build a synthetic system-level
	// context so the gateway still accepts the token.
	if !resolved.Valid() {
		sessionVersion, svErr := h.contextResolver.ResolveUserSessionVersion(ctx, user.ID)
		if svErr != nil {
			return loginTokenResult{}, fmt.Errorf("resolve session version: %w", svErr)
		}
		if sessionVersion <= 0 {
			return loginTokenResult{}, fmt.Errorf("invalid session version")
		}
		resolved = model.AuthorizationSessionContext{
			Actor: model.ActorContext{
				UserID:            user.ID,
				RootTenantID:      user.ID,
				OrganizationID:    user.ID,
				MembershipID:      user.ID,
				MembershipVersion: 1,
			},
			AuthorizationVersion: 1,
			SessionVersion:       sessionVersion,
			Phone:                user.Phone,
			IsSystemAdmin:        user.IsSystemAdmin,
		}
	}

	// Generate a session ID (JTI) shared by both tokens.
	sessionID, err := jwt.GenerateSessionID()
	if err != nil {
		return loginTokenResult{}, fmt.Errorf("generate session id: %w", err)
	}

	accessToken, err := h.jwtService.GenerateContextAccessTokenForSession(
		resolved.Actor.UserID, resolved.Actor.RootTenantID, resolved.Actor.OrganizationID,
		resolved.Actor.MembershipID, resolved.Actor.MembershipVersion,
		resolved.AuthorizationVersion, resolved.SessionVersion,
		sessionID, resolved.Phone, resolved.IsSystemAdmin,
	)
	if err != nil {
		return loginTokenResult{}, fmt.Errorf("generate access token: %w", err)
	}

	refreshToken, err := h.jwtService.GenerateRefreshTokenForSession(
		resolved.Actor.UserID, resolved.SessionVersion, sessionID,
	)
	if err != nil {
		return loginTokenResult{}, fmt.Errorf("generate refresh token: %w", err)
	}

	return loginTokenResult{
		AccessToken:          accessToken,
		RefreshToken:         refreshToken,
		ActiveOrganizationID: resolved.Actor.OrganizationID,
		RootTenantID:         resolved.Actor.RootTenantID,
		MembershipID:         resolved.Actor.MembershipID,
	}, nil
}

type LoginRequest struct {
	Account  string `json:"account" binding:"required"`
	Password string `json:"password" binding:"required"`
}

type LoginResponse struct {
	AccessToken          string      `json:"access_token"`
	RefreshToken         string      `json:"refresh_token"`
	User                 *model.User `json:"user"`
	ExpiresIn            int64       `json:"expires_in"`
	Permissions          []string    `json:"permissions"`
	IsSystemAdmin        bool        `json:"is_system_admin"`
	ActiveOrganizationID int64       `json:"active_organization_id,omitempty"`
	RootTenantID         int64       `json:"root_tenant_id,omitempty"`
	MembershipID         int64       `json:"membership_id,omitempty"`
}

// loadUserPermissions loads the user's permission codes from the new
// organization-based authorization system.  System admins receive a wildcard
// permission; regular users get their granted permission_codes from the
// membership role assignments.
func (h *AuthHandler) loadUserPermissions(ctx context.Context, userID int64, tokenResult loginTokenResult) []string {
	permissions := make([]string, 0)

	user, err := h.userService.GetByID(ctx, userID)
	if err != nil {
		logger.Warn("Failed to load user for permissions",
			zap.Int64("user_id", userID), zap.Error(err))
		return permissions
	}

	// System admins bypass all permission checks.
	if user.IsSystemAdmin {
		return []string{"*"}
	}

	// Load permission codes from the organization-based authorization system.
	if h.contextResolver == nil || tokenResult.ActiveOrganizationID <= 0 {
		return permissions
	}
	actor := model.ActorContext{
		UserID:            userID,
		RootTenantID:      tokenResult.RootTenantID,
		OrganizationID:    tokenResult.ActiveOrganizationID,
		MembershipID:      tokenResult.MembershipID,
		MembershipVersion: 1,
	}
	codes, err := h.contextResolver.LoadAllPermissionCodes(ctx, actor)
	if err != nil {
		logger.Warn("Failed to load permission codes",
			zap.Int64("user_id", userID), zap.Error(err))
		return permissions
	}
	return codes
}

func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
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

	tokenResult, err := h.generateLoginTokenPair(c.Request.Context(), user)
	if err != nil {
		response.Error(c, 500, "generate token failed")
		return
	}

	if err := h.jwtService.StoreRefreshToken(c.Request.Context(), user.ID, tokenResult.RefreshToken, refreshTokenLifetime); err != nil {
		response.Error(c, 500, "create refresh session failed")
		return
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
		h.cacheUserPermissions(ctx, user.ID)
	}()

	// 获取用户权限列表
	permissions := h.loadUserPermissions(c.Request.Context(), user.ID, tokenResult)

	// 设置 httpOnly cookie（同时返回 body 保持兼容）
	setAuthCookies(c, tokenResult.AccessToken, tokenResult.RefreshToken, accessTokenLifetime, refreshTokenLifetime)

	user.HasPassword = hasUsablePassword(user.PasswordHash)
	user.PasswordHash = ""
	response.Success(c, LoginResponse{
		AccessToken:          tokenResult.AccessToken,
		RefreshToken:         tokenResult.RefreshToken,
		User:                 user,
		ExpiresIn:            int64(accessTokenLifetime.Seconds()),
		Permissions:          permissions,
		IsSystemAdmin:        user.IsSystemAdmin,
		ActiveOrganizationID: tokenResult.ActiveOrganizationID,
		RootTenantID:         tokenResult.RootTenantID,
		MembershipID:         tokenResult.MembershipID,
	})
}

type RegisterRequest struct {
	Phone    string `json:"phone" binding:"required"`
	Code     string `json:"code" binding:"required"`
	Password string `json:"password" binding:"required,min=6,max=20"`
	Country  string `json:"country"` // 注册时选择的国家/地区代码（如 CN, US）
}

func (h *AuthHandler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	existingUser, err := h.userService.GetByPhone(c.Request.Context(), req.Phone)
	if err != nil {
		response.Error(c, 500, "system error")
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
		response.Error(c, 500, "password encryption failed")
		return
	}

	user := &model.User{
		Phone:        req.Phone,
		PasswordHash: string(hashedPassword),
		Status:       1,
		Country:      req.Country,
	}

	if err := h.userService.Create(c.Request.Context(), user); err != nil {
		response.Error(c, 500, "create user failed")
		return
	}

	tokenResult, err := h.generateLoginTokenPair(c.Request.Context(), user)
	if err != nil {
		response.Error(c, 500, "generate token failed")
		return
	}

	if err := h.jwtService.StoreRefreshToken(c.Request.Context(), user.ID, tokenResult.RefreshToken, refreshTokenLifetime); err != nil {
		response.Error(c, 500, "create refresh session failed")
		return
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
		h.cacheUserPermissions(ctx, user.ID)
	}()

	user.HasPassword = hasUsablePassword(user.PasswordHash)
	user.PasswordHash = ""
	permissions := h.loadUserPermissions(c.Request.Context(), user.ID, tokenResult)
	response.Success(c, LoginResponse{
		AccessToken:          tokenResult.AccessToken,
		RefreshToken:         tokenResult.RefreshToken,
		User:                 user,
		ExpiresIn:            int64(accessTokenLifetime.Seconds()),
		Permissions:          permissions,
		IsSystemAdmin:        user.IsSystemAdmin,
		ActiveOrganizationID: tokenResult.ActiveOrganizationID,
		RootTenantID:         tokenResult.RootTenantID,
		MembershipID:         tokenResult.MembershipID,
	})
}

type SendCodeRequest struct {
	Phone string `json:"phone" binding:"required"`
	Type  string `json:"type" binding:"required"`
}

func (h *AuthHandler) SendCode(c *gin.Context) {
	var req SendCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
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
		response.Error(c, 500, "system error")
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
		response.Error(c, 4006, "verification code delivery failed")
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
		response.Error(c, 400, "invalid request")
		return
	}

	user, err := h.userService.GetByPhone(c.Request.Context(), req.Phone)
	if err != nil {
		response.Error(c, 500, "system error")
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
		response.Error(c, 500, "password encryption failed")
		return
	}

	if err := h.userService.UpdatePassword(c.Request.Context(), user.ID, string(hashedPassword)); err != nil {
		response.Error(c, 500, "update password failed")
		return
	}
	if err := h.jwtService.RevokeAllUserTokens(c.Request.Context(), user.ID); err != nil {
		logger.Warn("refresh session cleanup failed after password reset", zap.Error(err))
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
		response.Error(c, 400, "invalid request")
		return
	}

	if !emailRegex.MatchString(req.Email) {
		response.Error(c, 4008, "invalid email format")
		return
	}

	user, err := h.userService.GetByEmail(c.Request.Context(), req.Email)
	if err != nil {
		response.Error(c, 500, "system error")
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
		response.Error(c, 500, "password encryption failed")
		return
	}

	if err := h.userService.UpdatePassword(c.Request.Context(), user.ID, string(hashedPassword)); err != nil {
		response.Error(c, 500, "update password failed")
		return
	}
	if err := h.jwtService.RevokeAllUserTokens(c.Request.Context(), user.ID); err != nil {
		logger.Warn("refresh session cleanup failed after password reset", zap.Error(err))
	}

	// 重置密码后，撤销该用户所有已有的 refresh token，强制重新登录
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		// 记录重置密码审计日志
		h.userService.LogAudit(ctx, user.ID, user.Nickname, "reset_password", "auth", "", "{}", c.ClientIP())
	}()

	response.SuccessWithMessage(c, "password reset success", nil)
}

type ChangePasswordRequest struct {
	// 无密码账号（如手机号验证码一键登录注册）允许旧密码为空，直接设置新密码
	OldPassword string `json:"old_password" binding:"omitempty"`
	NewPassword string `json:"new_password" binding:"required,min=6,max=20"`
}

// hasUsablePassword 判断账号是否已设置可用的 bcrypt 密码。
// 历史一键登录注册账号可能存有占位符（如 "\\"），不构成有效密码。
func hasUsablePassword(hash string) bool {
	if hash == "" {
		return false
	}
	_, err := bcrypt.Cost([]byte(hash))
	return err == nil
}

func (h *AuthHandler) ChangePassword(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req ChangePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	user, err := h.userService.GetByID(c.Request.Context(), userID)
	if err != nil {
		response.Error(c, 500, "system error")
		return
	}

	// 已设置密码的账号必须校验旧密码；无密码账号（一键登录注册）跳过旧密码校验
	if hasUsablePassword(user.PasswordHash) {
		if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.OldPassword)); err != nil {
			response.Error(c, 4007, "old password incorrect")
			return
		}
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		response.Error(c, 500, "password encryption failed")
		return
	}

	if err := h.userService.UpdatePassword(c.Request.Context(), userID, string(hashedPassword)); err != nil {
		response.Error(c, 500, "update password failed")
		return
	}
	if err := h.jwtService.RevokeAllUserTokens(c.Request.Context(), userID); err != nil {
		logger.Warn("refresh session cleanup failed after password change", zap.Error(err))
	}

	response.SuccessWithMessage(c, "password changed success", nil)
}

func (h *AuthHandler) GetProfile(c *gin.Context) {
	userID := middleware.GetUserID(c)

	user, err := h.userService.GetByID(c.Request.Context(), userID)
	if err != nil {
		response.Error(c, 500, "system error")
		return
	}

	if user == nil {
		response.Error(c, 404, "user not found")
		return
	}

	user.HasPassword = hasUsablePassword(user.PasswordHash)
	user.PasswordHash = ""
	response.Success(c, user)
}

type UpdateProfileRequest struct {
	Nickname   string `json:"nickname"`
	Avatar     string `json:"avatar"`
	Timezone   string `json:"timezone"`
	Country    string `json:"country"`
	RegionName string `json:"region_name"`
	Bio        string `json:"bio"`
	Phone      string `json:"phone"` // 可选：补充手机号（开发阶段，暂不校验短信验证码）
}

func (h *AuthHandler) UpdateProfile(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req UpdateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	// 验证时区
	if req.Timezone != "" {
		if err := timezone.ValidateTimezone(req.Timezone); err != nil {
			response.Error(c, 400, "invalid timezone: "+req.Timezone)
			return
		}
	}

	// 可选手机号：开发阶段暂不校验短信验证码
	if req.Phone != "" {
		if len(req.Phone) < 5 {
			response.Error(c, 400, "invalid phone number")
			return
		}
		// 查重：排除自己
		existingPhone, _ := h.userService.GetByPhone(c.Request.Context(), req.Phone)
		if existingPhone != nil && existingPhone.ID != userID {
			response.Error(c, 4004, "phone already registered")
			return
		}
	}

	if err := h.userService.UpdateProfile(c.Request.Context(), userID, req.Nickname, req.Avatar, req.Timezone, req.Country, req.RegionName, req.Bio); err != nil {
		response.Error(c, 500, "update profile failed")
		return
	}

	// 更新手机号（如有提供）
	if req.Phone != "" {
		if err := h.userService.UpdatePhone(c.Request.Context(), userID, req.Phone); err != nil {
			logger.Warn("update phone failed", zap.String("phone", req.Phone), zap.Error(err))
			response.Error(c, 500, "update phone failed")
			return
		}
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
		if claims, err := h.jwtService.ParseAccessToken(tokenStr); err == nil {
			jti := h.jwtService.GetJTI(claims)
			if jti != "" {
				h.jwtService.AddToBlacklist(c.Request.Context(), jti, accessTokenLifetime)
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

type AuthorizationContextRequest struct {
	OrganizationID int64  `json:"organization_id" binding:"required"`
	RefreshToken   string `json:"refresh_token,omitempty"`
}

func (h *AuthHandler) AuthorizationContext(c *gin.Context) {
	if h.contextResolver == nil {
		response.Error(c, 500, "authorization context resolver unavailable")
		return
	}
	var req AuthorizationContextRequest
	if err := c.ShouldBindJSON(&req); err != nil || req.OrganizationID <= 0 {
		response.Error(c, 400, "organization_id is required")
		return
	}
	if req.RefreshToken == "" {
		req.RefreshToken, _ = c.Cookie("refresh_token")
	}
	if req.RefreshToken == "" {
		response.Error(c, 401, "missing refresh token")
		return
	}

	refreshClaims, err := h.jwtService.ParseRefreshToken(req.RefreshToken)
	if err != nil {
		response.Error(c, 401, "invalid refresh session")
		return
	}
	resolved, err := h.contextResolver.ResolveAuthorizationSessionContext(c.Request.Context(), refreshClaims.UserID, req.OrganizationID)
	if err != nil || !resolved.Valid() || resolved.SessionVersion != refreshClaims.SessionVersion {
		response.Error(c, 401, "organization membership is not active")
		return
	}

	accessToken, err := h.jwtService.GenerateContextAccessTokenForSession(
		resolved.Actor.UserID, resolved.Actor.RootTenantID, resolved.Actor.OrganizationID,
		resolved.Actor.MembershipID, resolved.Actor.MembershipVersion,
		resolved.AuthorizationVersion, resolved.SessionVersion,
		refreshClaims.SessionID, resolved.Phone, resolved.IsSystemAdmin,
	)
	if err != nil {
		response.Error(c, 500, "generate access token failed")
		return
	}
	newRefreshToken, err := h.jwtService.GenerateRefreshTokenForSession(resolved.Actor.UserID, resolved.SessionVersion, refreshClaims.SessionID)
	if err != nil {
		response.Error(c, 500, "generate refresh token failed")
		return
	}
	swapped, swapErr := h.jwtService.SwapRefreshToken(c.Request.Context(), resolved.Actor.UserID, req.RefreshToken, newRefreshToken, refreshTokenLifetime)
	if swapErr == nil && !swapped {
		_ = h.jwtService.RevokeRefreshToken(c.Request.Context(), resolved.Actor.UserID, req.RefreshToken)
	}
	if err := requireRefreshSwap(swapped, swapErr); err != nil {
		response.Error(c, 500, err.Error())
		return
	}

	setAuthCookies(c, accessToken, newRefreshToken, accessTokenLifetime, refreshTokenLifetime)
	response.Success(c, gin.H{
		"access_token": accessToken, "refresh_token": newRefreshToken,
		"expires_in": 900, "active_organization_id": resolved.Actor.OrganizationID,
		"root_tenant_id":        resolved.Actor.RootTenantID,
		"membership_id":         resolved.Actor.MembershipID,
		"membership_version":    resolved.Actor.MembershipVersion,
		"authorization_version": resolved.AuthorizationVersion,
	})
}

func (h *AuthHandler) RefreshToken(c *gin.Context) {
	var req RefreshTokenRequest
	// 优先从 body 读取，其次从 cookie 读取
	if err := c.ShouldBindJSON(&req); err != nil || req.RefreshToken == "" {
		req.RefreshToken, _ = c.Cookie("refresh_token")
	}

	if req.RefreshToken == "" {
		response.Error(c, 400, "missing refresh token")
		return
	}

	claims, err := h.jwtService.ParseRefreshToken(req.RefreshToken)
	if err != nil {
		response.Error(c, 401, "invalid refresh token")
		return
	}

	if h.contextResolver == nil {
		response.Error(c, 500, "authorization context resolver unavailable")
		return
	}
	currentSessionVersion, err := h.contextResolver.ResolveUserSessionVersion(c.Request.Context(), claims.UserID)
	if err != nil || currentSessionVersion != claims.SessionVersion {
		response.Error(c, 401, "refresh session revoked")
		return
	}
	user, err := h.userService.GetByID(c.Request.Context(), claims.UserID)
	if err != nil || user == nil || user.Status != 1 {
		response.Error(c, 401, "refresh session revoked")
		return
	}

	// Resolve the user's current organization context to issue a
	// context-aware access token.  Fall back to a synthetic context
	// when no active membership exists.
	resolved, resolveErr := h.contextResolver.ResolveDefaultSessionContext(c.Request.Context(), claims.UserID)
	if resolveErr != nil && !errors.Is(resolveErr, pgx.ErrNoRows) {
		response.Error(c, 500, "resolve context failed")
		return
	}
	if !resolved.Valid() {
		resolved = model.AuthorizationSessionContext{
			Actor: model.ActorContext{
				UserID:            user.ID,
				RootTenantID:      user.ID,
				OrganizationID:    user.ID,
				MembershipID:      user.ID,
				MembershipVersion: 1,
			},
			AuthorizationVersion: 1,
			SessionVersion:       currentSessionVersion,
			Phone:                user.Phone,
			IsSystemAdmin:        user.IsSystemAdmin,
		}
	}

	newAccessToken, err := h.jwtService.GenerateContextAccessTokenForSession(
		resolved.Actor.UserID, resolved.Actor.RootTenantID, resolved.Actor.OrganizationID,
		resolved.Actor.MembershipID, resolved.Actor.MembershipVersion,
		resolved.AuthorizationVersion, resolved.SessionVersion,
		claims.SessionID, resolved.Phone, resolved.IsSystemAdmin,
	)
	if err != nil {
		response.Error(c, 500, "generate token failed")
		return
	}
	newRefreshToken, err := h.jwtService.GenerateRefreshTokenForSession(claims.UserID, currentSessionVersion, claims.SessionID)
	if err != nil {
		response.Error(c, 500, "generate refresh token failed")
		return
	}

	swapped, swapErr := h.jwtService.SwapRefreshToken(c.Request.Context(), claims.UserID, req.RefreshToken, newRefreshToken, refreshTokenLifetime)
	if swapErr == nil && !swapped {
		_ = h.jwtService.RevokeRefreshToken(c.Request.Context(), claims.UserID, req.RefreshToken)
	}
	if err := requireRefreshSwap(swapped, swapErr); err != nil {
		if _, ok := err.(*apperr.AppError); ok {
			response.Error(c, 500, err.Error())
			return
		}
		response.Error(c, 500, "token refresh failed")
		return
	}

	// 更新 httpOnly cookie
	setAuthCookies(c, newAccessToken, newRefreshToken, accessTokenLifetime, refreshTokenLifetime)

	response.Success(c, gin.H{
		"access_token":           newAccessToken,
		"refresh_token":          newRefreshToken,
		"expires_in":             int64(accessTokenLifetime.Seconds()),
		"active_organization_id": resolved.Actor.OrganizationID,
		"root_tenant_id":         resolved.Actor.RootTenantID,
		"membership_id":          resolved.Actor.MembershipID,
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
		response.Error(c, 400, "invalid request")
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
		response.Error(c, 500, "system error")
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
		// 区分配置错误和网络错误，提供更友好的错误信息
		errMsg := "验证码发送失败，请稍后重试"
		if strings.Contains(err.Error(), "配置错误") {
			errMsg = "邮件服务配置错误，请联系管理员"
		}
		response.Error(c, 4010, errMsg)
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
	Phone    string `json:"phone"`    // 可选：海外用户纯邮箱注册无需手机号
	Nickname string `json:"nickname"` // 可选：为空时以邮箱前缀兜底
	Country  string `json:"country"`  // 注册时选择的国家/地区代码（如 CN, US）
}

func (h *AuthHandler) EmailRegister(c *gin.Context) {
	var req EmailRegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	if !emailRegex.MatchString(req.Email) {
		response.Error(c, 4008, "invalid email format")
		return
	}

	// 手机号可选：仅在填写时校验格式与唯一性
	if req.Phone != "" && len(req.Phone) < 5 {
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

	if req.Phone != "" {
		existingPhone, _ := h.userService.GetByPhone(c.Request.Context(), req.Phone)
		if existingPhone != nil {
			response.Error(c, 4004, "phone already registered")
			return
		}
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		response.Error(c, 500, "password encryption failed")
		return
	}

	// 昵称为空时以邮箱前缀兜底，保证个人资料页有展示名
	nickname := req.Nickname
	if nickname == "" {
		nickname = strings.Split(req.Email, "@")[0]
	}

	user := &model.User{
		Phone:        req.Phone,
		Email:        req.Email,
		PasswordHash: string(hashedPassword),
		Nickname:     nickname,
		Status:       1,
		Country:      req.Country,
	}

	if err := h.userService.Create(c.Request.Context(), user); err != nil {
		logger.Error("create user failed", zap.String("email", req.Email), zap.Error(err))
		response.Error(c, 500, "创建用户失败，请稍后重试")
		return
	}

	tokenResult, err := h.generateLoginTokenPair(c.Request.Context(), user)
	if err != nil {
		response.Error(c, 500, "generate token failed")
		return
	}

	if err := h.jwtService.StoreRefreshToken(c.Request.Context(), user.ID, tokenResult.RefreshToken, refreshTokenLifetime); err != nil {
		response.Error(c, 500, "create refresh session failed")
		return
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
		h.cacheUserPermissions(ctx, user.ID)
	}()

	user.HasPassword = hasUsablePassword(user.PasswordHash)
	user.PasswordHash = ""
	permissions := h.loadUserPermissions(c.Request.Context(), user.ID, tokenResult)
	response.Success(c, LoginResponse{
		AccessToken:          tokenResult.AccessToken,
		RefreshToken:         tokenResult.RefreshToken,
		User:                 user,
		ExpiresIn:            int64(accessTokenLifetime.Seconds()),
		Permissions:          permissions,
		IsSystemAdmin:        user.IsSystemAdmin,
		ActiveOrganizationID: tokenResult.ActiveOrganizationID,
		RootTenantID:         tokenResult.RootTenantID,
		MembershipID:         tokenResult.MembershipID,
	})
}

type EmailLoginRequest struct {
	Email    string `json:"email" binding:"required"`
	Password string `json:"password" binding:"required"`
}

func (h *AuthHandler) EmailLogin(c *gin.Context) {
	var req EmailLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
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
		response.Error(c, 500, "system error")
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

	tokenResult, err := h.generateLoginTokenPair(c.Request.Context(), user)
	if err != nil {
		response.Error(c, 500, "generate token failed")
		return
	}

	if err := h.jwtService.StoreRefreshToken(c.Request.Context(), user.ID, tokenResult.RefreshToken, refreshTokenLifetime); err != nil {
		response.Error(c, 500, "create refresh session failed")
		return
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
		h.cacheUserPermissions(ctx, user.ID)
	}()

	user.HasPassword = hasUsablePassword(user.PasswordHash)
	user.PasswordHash = ""
	permissions := h.loadUserPermissions(c.Request.Context(), user.ID, tokenResult)
	response.Success(c, LoginResponse{
		AccessToken:          tokenResult.AccessToken,
		RefreshToken:         tokenResult.RefreshToken,
		User:                 user,
		ExpiresIn:            int64(accessTokenLifetime.Seconds()),
		Permissions:          permissions,
		IsSystemAdmin:        user.IsSystemAdmin,
		ActiveOrganizationID: tokenResult.ActiveOrganizationID,
		RootTenantID:         tokenResult.RootTenantID,
		MembershipID:         tokenResult.MembershipID,
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
		response.Error(c, 400, "invalid request")
		return
	}

	// 验证短信验证码
	if !h.smsService.VerifyCode(c.Request.Context(), req.Phone, req.Code, "login") {
		response.Error(c, 4005, "验证码错误或已过期")
		return
	}

	user, err := h.userService.GetByPhone(c.Request.Context(), req.Phone)
	if err != nil {
		response.Error(c, 500, "system error")
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
	tokenResult, err := h.generateLoginTokenPair(c.Request.Context(), user)
	if err != nil {
		response.Error(c, 500, "generate token failed")
		return
	}

	if err := h.jwtService.StoreRefreshToken(c.Request.Context(), user.ID, tokenResult.RefreshToken, refreshTokenLifetime); err != nil {
		response.Error(c, 500, "create refresh session failed")
		return
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
		h.cacheUserPermissions(ctx, user.ID)
	}()

	permissions := h.loadUserPermissions(c.Request.Context(), user.ID, tokenResult)

	setAuthCookies(c, tokenResult.AccessToken, tokenResult.RefreshToken, accessTokenLifetime, refreshTokenLifetime)

	user.HasPassword = hasUsablePassword(user.PasswordHash)
	user.PasswordHash = ""
	response.Success(c, LoginResponse{
		AccessToken:          tokenResult.AccessToken,
		RefreshToken:         tokenResult.RefreshToken,
		User:                 user,
		ExpiresIn:            int64(accessTokenLifetime.Seconds()),
		Permissions:          permissions,
		IsSystemAdmin:        user.IsSystemAdmin,
		ActiveOrganizationID: tokenResult.ActiveOrganizationID,
		RootTenantID:         tokenResult.RootTenantID,
		MembershipID:         tokenResult.MembershipID,
	})
}

// JVerifyLogin 极光认证一键登录
// 客户端通过运营商 SDK 获取 loginToken，后端验证并解密手机号，
// 用户不存在时自动创建（无需密码，可通过“忘记密码”设置）。
type JVerifyLoginRequest struct {
	LoginToken string `json:"login_token" binding:"required"`
}

func (h *AuthHandler) JVerifyLogin(c *gin.Context) {
	if !h.jverifyService.IsEnabled() {
		response.Error(c, 503, "one-click login service unavailable")
		return
	}

	var req JVerifyLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	// 验证 loginToken 并解密手机号
	phone, err := h.jverifyService.VerifyLoginToken(c.Request.Context(), req.LoginToken)
	if err != nil {
		logger.Warn("JVerify token verification failed", zap.Error(err))
		response.Error(c, 4006, "one-click login verification failed, please try again")
		return
	}

	// 查找用户
	user, err := h.userService.GetByPhone(c.Request.Context(), phone)
	if err != nil {
		response.Error(c, 500, "system error")
		return
	}

	// 用户不存在则自动创建
	if user == nil {
		user = &model.User{
			Phone:  phone,
			Status: 1,
		}
		if err := h.userService.Create(c.Request.Context(), user); err != nil {
			response.Error(c, 500, "create user failed")
			return
		}
	}

	if user.Status != 1 {
		response.Error(c, 4002, "account disabled")
		return
	}

	// 生成 token
	tokenResult, err := h.generateLoginTokenPair(c.Request.Context(), user)
	if err != nil {
		response.Error(c, 500, "generate token failed")
		return
	}

	if err := h.jwtService.StoreRefreshToken(c.Request.Context(), user.ID, tokenResult.RefreshToken, refreshTokenLifetime); err != nil {
		response.Error(c, 500, "create refresh session failed")
		return
	}

	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := h.userService.UpdateLoginInfo(ctx, user.ID, c.ClientIP()); err != nil {
			logger.Warn("UpdateLoginInfo failed", zap.Error(err))
		}
		h.userService.LogAudit(ctx, user.ID, user.Nickname, "login_by_jverify", "auth", "", "{}", c.ClientIP())
	}()
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		h.cacheUserPermissions(ctx, user.ID)
	}()

	permissions := h.loadUserPermissions(c.Request.Context(), user.ID, tokenResult)

	setAuthCookies(c, tokenResult.AccessToken, tokenResult.RefreshToken, accessTokenLifetime, refreshTokenLifetime)

	user.HasPassword = hasUsablePassword(user.PasswordHash)
	user.PasswordHash = ""
	response.Success(c, LoginResponse{
		AccessToken:          tokenResult.AccessToken,
		RefreshToken:         tokenResult.RefreshToken,
		User:                 user,
		ExpiresIn:            int64(accessTokenLifetime.Seconds()),
		Permissions:          permissions,
		IsSystemAdmin:        user.IsSystemAdmin,
		ActiveOrganizationID: tokenResult.ActiveOrganizationID,
		RootTenantID:         tokenResult.RootTenantID,
		MembershipID:         tokenResult.MembershipID,
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
		response.Error(c, 400, "invalid request")
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
		response.Error(c, 500, "system error")
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

	tokenResult, err := h.generateLoginTokenPair(c.Request.Context(), user)
	if err != nil {
		response.Error(c, 500, "generate token failed")
		return
	}

	if err := h.jwtService.StoreRefreshToken(c.Request.Context(), user.ID, tokenResult.RefreshToken, refreshTokenLifetime); err != nil {
		response.Error(c, 500, "create refresh session failed")
		return
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
		h.cacheUserPermissions(ctx, user.ID)
	}()

	permissions := h.loadUserPermissions(c.Request.Context(), user.ID, tokenResult)

	setAuthCookies(c, tokenResult.AccessToken, tokenResult.RefreshToken, accessTokenLifetime, refreshTokenLifetime)

	user.HasPassword = hasUsablePassword(user.PasswordHash)
	user.PasswordHash = ""
	response.Success(c, LoginResponse{
		AccessToken:          tokenResult.AccessToken,
		RefreshToken:         tokenResult.RefreshToken,
		User:                 user,
		ExpiresIn:            int64(accessTokenLifetime.Seconds()),
		Permissions:          permissions,
		IsSystemAdmin:        user.IsSystemAdmin,
		ActiveOrganizationID: tokenResult.ActiveOrganizationID,
		RootTenantID:         tokenResult.RootTenantID,
		MembershipID:         tokenResult.MembershipID,
	})
}

// ==================== 更改手机号/邮箱 ====================

// SendPhoneChangeCode 发送更改手机号验证码（已登录用户）
// POST /api/v1/auth/send-phone-code
type SendPhoneChangeCodeRequest struct {
	Phone string `json:"phone" binding:"required"`
}

func (h *AuthHandler) SendPhoneChangeCode(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID <= 0 {
		response.Error(c, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req SendPhoneChangeCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	if len(req.Phone) < 5 {
		response.Error(c, 400, "invalid phone number")
		return
	}

	// 检查手机号是否已被其他用户使用
	existingUser, err := h.userService.GetByPhone(c.Request.Context(), req.Phone)
	if err != nil {
		response.Error(c, 500, "system error")
		return
	}
	if existingUser != nil && existingUser.ID != userID {
		response.Error(c, 4009, "该手机号已被其他账户使用")
		return
	}

	// IP 级频率限制
	ipLimitKey := fmt.Sprintf("send_code_ip:%s", c.ClientIP())
	ipCount, _ := h.userService.Cache().Get(c.Request.Context(), ipLimitKey).Int()
	if ipCount >= 10 {
		response.Error(c, 4029, "发送验证码过于频繁，请稍后再试")
		return
	}

	if err := h.smsService.SendCode(c.Request.Context(), req.Phone, "change_phone"); err != nil {
		logger.Warn("send phone change code failed", zap.String("phone", req.Phone), zap.Error(err))
		response.Error(c, 4006, "verification code delivery failed")
		return
	}

	h.userService.Cache().Incr(c.Request.Context(), ipLimitKey)
	h.userService.Cache().Expire(c.Request.Context(), ipLimitKey, 1*time.Hour)

	response.SuccessWithMessage(c, "code sent", nil)
}

// SendEmailChangeCode 发送更改邮箱验证码（已登录用户）
// POST /api/v1/auth/send-email-change-code
type SendEmailChangeCodeRequest struct {
	Email string `json:"email" binding:"required"`
}

func (h *AuthHandler) SendEmailChangeCode(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID <= 0 {
		response.Error(c, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req SendEmailChangeCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	if !emailRegex.MatchString(req.Email) {
		response.Error(c, 4008, "invalid email format")
		return
	}

	// 检查邮箱是否已被其他用户使用
	existingUser, err := h.userService.GetByEmail(c.Request.Context(), req.Email)
	if err != nil {
		response.Error(c, 500, "system error")
		return
	}
	if existingUser != nil && existingUser.ID != userID {
		response.Error(c, 4009, "该邮箱已被其他账户使用")
		return
	}

	// IP 级频率限制
	ipLimitKey := fmt.Sprintf("send_code_ip:%s", c.ClientIP())
	ipCount, _ := h.userService.Cache().Get(c.Request.Context(), ipLimitKey).Int()
	if ipCount >= 10 {
		response.Error(c, 4029, "发送验证码过于频繁，请稍后再试")
		return
	}

	if err := h.emailService.SendCode(c.Request.Context(), req.Email, "change_email"); err != nil {
		logger.Warn("send email change code failed", zap.String("email", req.Email), zap.Error(err))
		// 区分配置错误和网络错误，提供更友好的错误信息
		errMsg := "验证码发送失败，请稍后重试"
		if strings.Contains(err.Error(), "配置错误") {
			errMsg = "邮件服务配置错误，请联系管理员"
		}
		response.Error(c, 4010, errMsg)
		return
	}

	h.userService.Cache().Incr(c.Request.Context(), ipLimitKey)
	h.userService.Cache().Expire(c.Request.Context(), ipLimitKey, 1*time.Hour)

	response.SuccessWithMessage(c, "code sent", nil)
}

// ChangePhone 更改手机号
// PUT /api/v1/auth/change-phone
type ChangePhoneRequest struct {
	NewPhone string `json:"new_phone" binding:"required"`
	Code     string `json:"code" binding:"required"`
}

func (h *AuthHandler) ChangePhone(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID <= 0 {
		response.Error(c, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req ChangePhoneRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	if len(req.NewPhone) < 5 {
		response.Error(c, 400, "invalid phone number")
		return
	}

	// 验证验证码
	if !h.smsService.VerifyCode(c.Request.Context(), req.NewPhone, req.Code, "change_phone") {
		response.Error(c, 4005, "验证码错误或已过期")
		return
	}

	// 检查手机号是否已被其他用户使用
	existingUser, err := h.userService.GetByPhone(c.Request.Context(), req.NewPhone)
	if err != nil {
		response.Error(c, 500, "system error")
		return
	}
	if existingUser != nil && existingUser.ID != userID {
		response.Error(c, 4009, "该手机号已被其他账户使用")
		return
	}

	// 更新手机号
	if err := h.userService.UpdatePhone(c.Request.Context(), userID, req.NewPhone); err != nil {
		logger.Error("update phone failed", zap.Int64("userID", userID), zap.Error(err))
		response.Error(c, 500, "更新手机号失败")
		return
	}

	// 记录审计日志
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		h.userService.LogAudit(ctx, userID, "", "change_phone", "auth", "", "{}", c.ClientIP())
	}()

	response.SuccessWithMessage(c, "手机号更改成功", nil)
}

// ChangeEmail 更改邮箱
// PUT /api/v1/auth/change-email
type ChangeEmailRequest struct {
	NewEmail string `json:"new_email" binding:"required"`
	Code     string `json:"code" binding:"required"`
}

func (h *AuthHandler) ChangeEmail(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID <= 0 {
		response.Error(c, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req ChangeEmailRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	if !emailRegex.MatchString(req.NewEmail) {
		response.Error(c, 4008, "invalid email format")
		return
	}

	// 验证验证码
	if !h.emailService.VerifyCode(c.Request.Context(), req.NewEmail, req.Code, "change_email") {
		response.Error(c, 4005, "验证码错误或已过期")
		return
	}

	// 检查邮箱是否已被其他用户使用
	existingUser, err := h.userService.GetByEmail(c.Request.Context(), req.NewEmail)
	if err != nil {
		response.Error(c, 500, "system error")
		return
	}
	if existingUser != nil && existingUser.ID != userID {
		response.Error(c, 4009, "该邮箱已被其他账户使用")
		return
	}

	// 更新邮箱
	if err := h.userService.UpdateEmail(c.Request.Context(), userID, req.NewEmail); err != nil {
		logger.Error("update email failed", zap.Int64("userID", userID), zap.Error(err))
		response.Error(c, 500, "更新邮箱失败")
		return
	}

	// 记录审计日志
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		h.userService.LogAudit(ctx, userID, "", "change_email", "auth", "", "{}", c.ClientIP())
	}()

	response.SuccessWithMessage(c, "邮箱更改成功", nil)
}
