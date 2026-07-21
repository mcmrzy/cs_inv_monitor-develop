import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 获取最近的完整日志（不限过滤）
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker logs inv-api-server --tail 5 2>&1")
print("=== 最近日�?===")
print(stdout.read().decode())

# �?curl 测试发送邮件接口（带完整错误）
stdin, stdout, stderr = client.exec_command("""curl -s -v -X POST 'http://127.0.0.1:8081/api/v1/auth/send-email-code' -H 'Content-Type: application/json' -d '{"email":"ops@example.invalid"}' 2>&1""")
print("\n=== 完整测试 ===")
print(stdout.read().decode())

client.close()
