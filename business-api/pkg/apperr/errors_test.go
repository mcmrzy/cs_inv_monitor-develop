package apperr

import (
	"errors"
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
)

// ==================== 工厂函数 ====================

func TestBadRequest_返回400错误(t *testing.T) {
	err := BadRequest("invalid phone")
	assert.Equal(t, http.StatusBadRequest, err.HTTPCode)
	assert.Equal(t, 400, err.BizCode)
	assert.Equal(t, "invalid phone", err.Message)
	assert.Nil(t, err.Err)
}

func TestBadRequestf_格式化消息(t *testing.T) {
	err := BadRequestf("field %s is required", "email")
	assert.Equal(t, http.StatusBadRequest, err.HTTPCode)
	assert.Equal(t, "field email is required", err.Message)
}

func TestNotFound_返回404错误(t *testing.T) {
	err := NotFound("device not found")
	assert.Equal(t, http.StatusNotFound, err.HTTPCode)
	assert.Equal(t, 404, err.BizCode)
	assert.Equal(t, "device not found", err.Message)
}

func TestUnauthorized_返回401错误(t *testing.T) {
	err := Unauthorized("token expired")
	assert.Equal(t, http.StatusUnauthorized, err.HTTPCode)
	assert.Equal(t, 401, err.BizCode)
	assert.Equal(t, "token expired", err.Message)
}

func TestForbidden_返回403错误(t *testing.T) {
	err := Forbidden("permission denied")
	assert.Equal(t, http.StatusForbidden, err.HTTPCode)
	assert.Equal(t, 403, err.BizCode)
	assert.Equal(t, "permission denied", err.Message)
}

func TestInternal_返回500错误并包装原始错误(t *testing.T) {
	origErr := errors.New("db connection refused")
	err := Internal("database error", origErr)

	assert.Equal(t, http.StatusInternalServerError, err.HTTPCode)
	assert.Equal(t, 500, err.BizCode)
	assert.Equal(t, "database error", err.Message)
	assert.Equal(t, origErr, err.Err)
}

func TestConflict_返回409错误(t *testing.T) {
	err := Conflict("resource already exists")
	assert.Equal(t, http.StatusConflict, err.HTTPCode)
	assert.Equal(t, 409, err.BizCode)
}

// ==================== Error() 方法 ====================

func TestAppError_Error_包含原始错误信息(t *testing.T) {
	origErr := errors.New("timeout")
	err := Internal("query failed", origErr)
	assert.Equal(t, "query failed: timeout", err.Error())
}

func TestAppError_Error_无原始错误时仅返回消息(t *testing.T) {
	err := BadRequest("bad input")
	assert.Equal(t, "bad input", err.Error())
}

// ==================== Unwrap() ====================

func TestAppError_Unwrap_返回原始错误(t *testing.T) {
	origErr := errors.New("underlying error")
	err := Internal("wrapper", origErr)

	unwrapped := err.Unwrap()
	assert.Equal(t, origErr, unwrapped)
}

func TestAppError_Unwrap_无原始错误返回nil(t *testing.T) {
	err := NotFound("not found")
	assert.Nil(t, err.Unwrap())
}

// ==================== errors.As 兼容 ====================

func TestAppError_ErrorsAs_兼容(t *testing.T) {
	err := BadRequest("test")
	var appErr *AppError
	assert.True(t, errors.As(err, &appErr))
	assert.Equal(t, "test", appErr.Message)
}

func TestAppError_ErrorsIs_兼容(t *testing.T) {
	origErr := errors.New("original")
	err := Internal("wrapped", origErr)
	assert.True(t, errors.Is(err, origErr))
}

// ==================== WithBizCode ====================

func TestWithBizCode_覆盖业务码(t *testing.T) {
	err := BadRequest("custom code").WithBizCode(10001)
	assert.Equal(t, http.StatusBadRequest, err.HTTPCode)
	assert.Equal(t, 10001, err.BizCode)
}

func TestWithBizCode_支持链式调用(t *testing.T) {
	err := NotFound("item").WithBizCode(40401)
	assert.Equal(t, 40401, err.BizCode)
	assert.Equal(t, "item", err.Message)
}

// ==================== 表驱动：全场景 ====================

func TestAllErrorTypes_表驱动(t *testing.T) {
	tests := []struct {
		name     string
		err      *AppError
		httpCode int
		bizCode  int
	}{
		{"BadRequest", BadRequest("bad"), 400, 400},
		{"NotFound", NotFound("nf"), 404, 404},
		{"Unauthorized", Unauthorized("ua"), 401, 401},
		{"Forbidden", Forbidden("fb"), 403, 403},
		{"Internal", Internal("ie", nil), 500, 500},
		{"Conflict", Conflict("cf"), 409, 409},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			assert.Equal(t, tc.httpCode, tc.err.HTTPCode)
			assert.Equal(t, tc.bizCode, tc.err.BizCode)
		})
	}
}
