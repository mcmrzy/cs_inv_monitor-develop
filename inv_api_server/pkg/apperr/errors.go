// Package apperr 提供统一的业务错误类型，用于 Handler 层的错误处理。
//
// 用法：
//
//	return apperr.BadRequest("invalid phone number")
//	return apperr.NotFound("device not found")
//	return apperr.Internal("database error", err)
//	return apperr.Unauthorized("token expired")
package apperr

import (
	"fmt"
	"net/http"
)

// AppError 表示一个业务错误，包含 HTTP 状态码、业务码、消息和原始错误。
type AppError struct {
	HTTPCode int    `json:"-"`
	BizCode  int    `json:"code"`
	Message  string `json:"message"`
	Err      error  `json:"-"`
}

func (e *AppError) Error() string {
	if e.Err != nil {
		return fmt.Sprintf("%s: %v", e.Message, e.Err)
	}
	return e.Message
}

func (e *AppError) Unwrap() error { return e.Err }

// BadRequest 400 参数错误
func BadRequest(msg string) *AppError {
	return &AppError{HTTPCode: http.StatusBadRequest, BizCode: 400, Message: msg}
}

// BadRequestf 400 参数错误（格式化消息）
func BadRequestf(format string, args ...interface{}) *AppError {
	return BadRequest(fmt.Sprintf(format, args...))
}

// NotFound 404 资源未找到
func NotFound(msg string) *AppError {
	return &AppError{HTTPCode: http.StatusNotFound, BizCode: 404, Message: msg}
}

// Unauthorized 401 未认证
func Unauthorized(msg string) *AppError {
	return &AppError{HTTPCode: http.StatusUnauthorized, BizCode: 401, Message: msg}
}

// Forbidden 403 无权限
func Forbidden(msg string) *AppError {
	return &AppError{HTTPCode: http.StatusForbidden, BizCode: 403, Message: msg}
}

// Internal 500 内部错误
func Internal(msg string, err error) *AppError {
	return &AppError{HTTPCode: http.StatusInternalServerError, BizCode: 500, Message: msg, Err: err}
}

// Conflict 409 资源冲突
func Conflict(msg string) *AppError {
	return &AppError{HTTPCode: http.StatusConflict, BizCode: 409, Message: msg}
}

// WithBizCode 设置自定义业务码
func (e *AppError) WithBizCode(code int) *AppError {
	e.BizCode = code
	return e
}
