import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 检�?users 表是否存�?
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c '\\dt users*'")
print("=== users �?===")
print(stdout.read().decode())

# 检查所有表
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c '\\dt'")
print("\n=== 所有表 ===")
print(stdout.read().decode())

# 尝试查询用户
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c \"SELECT id, email FROM users LIMIT 5;\"")
print("\n=== 查询用户 ===")
print(stdout.read().decode())
print(stderr.read().decode())

client.close()
