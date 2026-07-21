import paramiko
import time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 先清空日�?
client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S bash -c 'truncate -s 0 $(docker inspect --format=\"{{.LogPath}}\" inv-api-server)'")

time.sleep(2)

# 模拟完整浏览器请求（带滑块验证token�?
test_cmd = """curl -s -w '\\nHTTP_CODE:%{http_code}' -X POST 'http://127.0.0.1:8888/api/v1/auth/send-email-code' \
  -H 'Content-Type: application/json' \
  -H 'X-Captcha-Token: browser-test-token' \
  -H 'Origin: http://example.invalid:3000' \
  -H 'Referer: http://example.invalid:3000/' \
  -d '{"email":"ops@example.invalid","type":"register"}'"""

stdin, stdout, stderr = client.exec_command(test_cmd)
print("=== 测试结果 ===")
print(stdout.read().decode())

time.sleep(2)

# 获取所有新日志
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker logs inv-api-server --tail 30 2>&1")
print("\n=== API Server 完整日志 ===")
print(stdout.read().decode())

client.close()
