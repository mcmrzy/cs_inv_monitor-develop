import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

# 测试 SMTP 连接
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec inv-api-server sh -c 'nc -zv smtp.qq.com 465 2>&1 || echo SMTP_FAILED'")
print("=== SMTP 连接测试 ===")
print(stdout.read().decode())

# 查看 API Server 完整错误日志
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker logs inv-api-server 2>&1 | grep -i -E 'error|fail|panic|500|email|smtp|redis' | tail -20")
print("\n=== API Server 错误日志 ===")
print(stdout.read().decode())

# 测试 Redis 连接
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec inv-api-server sh -c 'wget -qO- http://inv-api-server:8080/health 2>&1 || echo NO_HEALTH'")
print("\n=== 健康检查 ===")
print(stdout.read().decode())

client.close()
