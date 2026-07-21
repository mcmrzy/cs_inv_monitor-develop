import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 查看 API 服务日志
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker logs inv-api-server --tail 50 2>&1 | grep -i -E 'email|mail|smtp|error|500'")
print("=== API Server 邮件相关日志 ===")
print(stdout.read().decode())

# 查看 .env 中的邮件配置
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-api-server env | grep -i EMAIL")
print("\n=== 容器内邮件环境变�?===")
print(stdout.read().decode())

client.close()
