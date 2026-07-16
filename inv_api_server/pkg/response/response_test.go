package response

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"inv-api-server/pkg/apperr"

	"github.com/gin-gonic/gin"
)

func TestHandleErrorDoesNotExposeInternalCause(t *testing.T) {
	gin.SetMode(gin.TestMode)
	recorder := httptest.NewRecorder()
	context, _ := gin.CreateTestContext(recorder)

	const publicMessage = "操作失败，请稍后重试"
	const privateCause = "password=secret host=private-db"
	HandleError(context, apperr.Internal(publicMessage, errors.New(privateCause)))

	if recorder.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusInternalServerError)
	}
	if strings.Contains(recorder.Body.String(), privateCause) {
		t.Fatalf("response exposed internal cause: %s", recorder.Body.String())
	}

	var body Response
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.Code != http.StatusInternalServerError || body.Message != publicMessage {
		t.Fatalf("response = %#v", body)
	}
}

func TestHandleErrorUsesGenericMessageForUnknownErrors(t *testing.T) {
	gin.SetMode(gin.TestMode)
	recorder := httptest.NewRecorder()
	context, _ := gin.CreateTestContext(recorder)

	const privateCause = "sql: connection string leaked"
	HandleError(context, errors.New(privateCause))

	if strings.Contains(recorder.Body.String(), privateCause) {
		t.Fatalf("response exposed unknown error: %s", recorder.Body.String())
	}
}
