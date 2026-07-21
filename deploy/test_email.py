import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 测试发送邮件验证码（带正确参数�?
stdin, stdout, stderr = client.exec_command("""curl -s -X POST 'http://127.0.0.1:8081/api/v1/auth/send-email-code' -H 'Content-Type: application/json' -H 'X-Captcha-Token: test' -d '{"email":"ops@example.invalid","type":"register"}' 2>&1""")
print("=== 测试结果 ===")
print(stdout.read().decode())

# 查看最新日�?
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker logs inv-api-server --tail 5 2>&1")
print("\n=== 最新日�?===")
print(stdout.read().decode())

client.close()
