package service

import (
	"fmt"
	"net/url"
	"regexp"
)

// 设备端对固件下载地址的约束来自 ESP-IDF 自带的 http_parser：esp_http_client_set_url()
// 的第一步就是 http_parser_parse_url()，而它编译时带 HTTP_PARSER_STRICT=1。用 IDF 自带
// 的 parser 在宿主上实测，下列形态会让解析失败（或解析通过但主机为空）：
//   - 路径含空格；
//   - 路径含非 ASCII（中文）字节；
//   - 主机名带下划线（STRICT 下 IS_HOST_CHAR 只认字母数字、'.'、'-'）；
//   - 主机缺失（如 https:///x.bin）。
//
// 任一命中都会让 esp_http_client_init() 返回 NULL，设备只回报一句
// "HTTP client init failed"（进度 0%；且 ota/debug trace 都在 if (client) 里，
// 连留痕都没有），云端完全看不出原因。所以在这里于下发前拦掉，
// 把真正的原因留在服务端日志和升级记录的 error_message 里。
var deviceURLHostPattern = regexp.MustCompile(`^[A-Za-z0-9.:-]+$`)

// deviceURLUnsafeByte 返回 URL 中第一个设备端解析器不接受的字节（空格、控制字符、非 ASCII）。
// 百分号转义（如 %20）是 ASCII，因此合法；浏览器会自动编码、设备不会，这正是本缺陷能潜伏的原因。
func deviceURLUnsafeByte(raw string) (byte, bool) {
	for i := 0; i < len(raw); i++ {
		if c := raw[i]; c <= 0x20 || c >= 0x7f {
			return c, true
		}
	}
	return 0, false
}

// ValidateDeviceDownloadURL 校验即将随 OTA 命令下发给设备的固件下载地址。
// 返回 nil 表示设备端 http_parser 一定能解析：空串、相对路径、缺主机名、
// 非 http(s) 协议一律拒绝。
func ValidateDeviceDownloadURL(raw string) error {
	if raw == "" {
		return fmt.Errorf("固件下载地址为空")
	}
	if c, bad := deviceURLUnsafeByte(raw); bad {
		return fmt.Errorf("固件下载地址含空格或非 ASCII 字节（%q）", string([]byte{c}))
	}
	u, err := url.Parse(raw)
	if err != nil {
		return fmt.Errorf("固件下载地址无法解析: %w", err)
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return fmt.Errorf("固件下载地址必须以 http:// 或 https:// 开头（当前 %q）", raw)
	}
	host := u.Hostname()
	if host == "" {
		return fmt.Errorf("固件下载地址缺少主机名（%q）", raw)
	}
	if !deviceURLHostPattern.MatchString(host) {
		return fmt.Errorf("固件下载地址主机名含设备不支持的字符（%q）", host)
	}
	return nil
}
