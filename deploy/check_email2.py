import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 查看 API 网关日志（请求经过网关）
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker logs inv-api-gateway --tail 30 2>&1 | grep -i -E 'email|500|error|send'")
print("=== API Gateway 日志 ===")
print(stdout.read().decode())

# 查看 API Server 最近日志（不限过滤�?
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker logs inv-api-server --tail 10 2>&1")
print("\n=== API Server 最近日�?===")
print(stdout.read().decode())

# 测试邮件发送接�?
stdin, stdout, stderr = client.exec_command("curl -s -X POST http://localhost:8888/api/v1/auth/send-email-code -H 'Content-Type: application/json' -d '{\"email\":\"test@test.com\"}' 2>&1")
print("\n=== 测试邮件接口 ===")
print(stdout.read().decode())

client.close()
