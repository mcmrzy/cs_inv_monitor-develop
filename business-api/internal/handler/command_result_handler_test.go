package handler

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestCommandConflictDoesNotTouchOriginalTask(t *testing.T) {
	// A nil database makes any accidental persistence of the conflict panic.
	h := &InternalHandler{}
	r := gin.New()
	r.POST("/result", h.DeviceCmdResult)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/result", bytes.NewBufferString(`{"sn":"SN001","task_id":"p0","stage":"failed","result":"IDEMPOTENCY_CONFLICT","err":-8}`)))
	assertResponseCode(t, w, 0)
	if !bytes.Contains(w.Body.Bytes(), []byte(`"ignored"`)) {
		t.Fatalf("conflict not ignored: %s", w.Body.String())
	}
}
