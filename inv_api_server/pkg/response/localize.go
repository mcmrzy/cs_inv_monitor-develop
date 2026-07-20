package response

import (
	"regexp"
	"strings"

	"github.com/gin-gonic/gin"
)

var chineseText = regexp.MustCompile(`[\p{Han}]`)
var retryMinutes = regexp.MustCompile(`^登录失败次数过多，请 (\d+) 分钟后再试$`)
var retrySeconds = regexp.MustCompile(`^请等待 (\d+) 秒后再发送$`)

var englishMessages = map[string]string{
	"角色更新成功":          "Role updated",
	"权限更新成功":          "Permissions updated",
	"权限配置保存成功":        "Permission configuration saved",
	"用户状态已更新":         "User status updated",
	"配置保存成功":          "Configuration saved",
	"配额更新成功":          "Quota updated",
	"租户状态已更新":         "Tenant status updated",
	"用户更新成功":          "User updated",
	"上级关系更新成功":        "Parent relationship updated",
	"请求过于频繁，请稍后再试":    "Too many requests. Try again later.",
	"滑动太快，请重试":        "The slider was moved too quickly. Try again.",
	"发送命令失败，请稍后重试":    "Failed to send the command. Try again later.",
	"需要验证码验证":         "Captcha verification is required",
	"请先完成滑块验证":        "Complete slider verification first",
	"发送验证码过于频繁，请稍后再试": "Verification codes are being requested too frequently. Try again later.",
	"该手机号未注册":         "This phone number is not registered",
	"该手机号已注册":         "This phone number is already registered",
	"该邮箱未注册":          "This email address is not registered",
	"该邮箱已注册":          "This email address is already registered",
	"验证码错误":           "Invalid verification code",
	"验证码错误或已过期":       "The verification code is invalid or expired",
	"固件上传成功":          "Firmware uploaded",
	"固件创建成功":          "Firmware created",
	"固件已删除":           "Firmware deleted",
	"升级已推送":           "Upgrade pushed",
	"已重试":             "Retry submitted",
	"已取消":             "Cancelled",
	"已删除":             "Deleted",
	"删除成功":            "Deleted",
	"灰度比例已更新":         "Rollout percentage updated",
	"版本已回滚":           "Version rolled back",
	"版本已恢复":           "Version restored",
	"升级包创建成功":         "Upgrade package created",
	"升级包已删除":          "Upgrade package deleted",
	"更新成功":            "Updated",
	"升级包已推送":          "Upgrade package pushed",
	"回滚指令已发送":         "Rollback command sent",
	"任务已执行":           "Task started",
	"任务已取消":           "Task cancelled",
	"任务已删除":           "Task deleted",
	"固件不存在":           "Firmware not found",
}

func localizeMessage(c *gin.Context, message, englishFallback string) string {
	if !wantsEnglish(c) || message == "" {
		return message
	}
	if translated, ok := englishMessages[message]; ok {
		return translated
	}
	if matches := retryMinutes.FindStringSubmatch(message); len(matches) == 2 {
		return "Too many failed login attempts. Try again in " + matches[1] + " minutes."
	}
	if matches := retrySeconds.FindStringSubmatch(message); len(matches) == 2 {
		return "Wait " + matches[1] + " seconds before requesting another code."
	}
	if strings.HasPrefix(message, "权限不足:") {
		return "Insufficient permission:" + strings.TrimPrefix(message, "权限不足:")
	}
	if chineseText.MatchString(message) {
		return englishFallback
	}
	return message
}

func wantsEnglish(c *gin.Context) bool {
	if c == nil || c.Request == nil {
		return false
	}
	header := strings.ToLower(strings.TrimSpace(c.GetHeader("Accept-Language")))
	return strings.HasPrefix(header, "en")
}
