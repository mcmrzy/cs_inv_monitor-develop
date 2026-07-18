import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 验证用户
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT id, phone, email, role FROM users;'")
print("=== 用户 ===")
print(stdout.read().decode())

# 验证权限
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT COUNT(*) FROM sys_permission;'")
print("=== 权限数量 ===")
print(stdout.read().decode())

stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT COUNT(*) FROM sys_role_permission;'")
print("=== 角色权限数量 ===")
print(stdout.read().decode())

# 验证设备
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT COUNT(*) FROM devices;'")
print("=== 设备数量 ===")
print(stdout.read().decode())

client.close()
