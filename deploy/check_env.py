import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='REDACTED_ROTATE_CREDENTIAL')

# 检查所有环境变量
stdin, stdout, stderr = client.exec_command("echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S docker exec inv-api-server env | sort")
print("=== API Server 环境变量 ===")
print(stdout.read().decode())

# 检查 traces export 错误
stdin, stdout, stderr = client.exec_command("echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S docker exec inv-api-server env | grep -i OTEL")
print("\n=== OTEL 配置 ===")
print(stdout.read().decode())

client.close()
