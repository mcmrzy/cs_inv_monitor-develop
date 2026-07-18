import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 检查所有环境变�?
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-api-server env | sort")
print("=== API Server 环境变量 ===")
print(stdout.read().decode())

# 检�?traces export 错误
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-api-server env | grep -i OTEL")
print("\n=== OTEL 配置 ===")
print(stdout.read().decode())

client.close()
