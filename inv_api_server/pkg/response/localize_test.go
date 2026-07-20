package response

import (
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func localizationContext(language string) *gin.Context {
	recorder := httptest.NewRecorder()
	context, _ := gin.CreateTestContext(recorder)
	context.Request = httptest.NewRequest("GET", "/", nil)
	context.Request.Header.Set("Accept-Language", language)
	return context
}

func TestLocalizeMessage(t *testing.T) {
	tests := []struct {
		name     string
		language string
		message  string
		want     string
	}{
		{name: "Chinese remains the default", language: "zh-CN", message: "升级包已推送", want: "升级包已推送"},
		{name: "English exact translation", language: "en-US,en;q=0.9", message: "升级包已推送", want: "Upgrade package pushed"},
		{name: "English dynamic retry", language: "en", message: "登录失败次数过多，请 7 分钟后再试", want: "Too many failed login attempts. Try again in 7 minutes."},
		{name: "English safe fallback", language: "en", message: "未收录的中文错误", want: "Request failed"},
		{name: "Language-neutral message remains", language: "en", message: "system error", want: "system error"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got := localizeMessage(localizationContext(test.language), test.message, "Request failed")
			if got != test.want {
				t.Fatalf("localizeMessage() = %q, want %q", got, test.want)
			}
		})
	}
}
