import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 检查用户角�?
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT id, phone, role, status FROM users;'")
print("=== 用户角色 ===")
print(stdout.read().decode())

# 检查权限表
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c '\\dt *perm*'")
print("=== 权限相关�?===")
print(stdout.read().decode())

# 检�?role_permissions 数据
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT * FROM role_permissions LIMIT 10;'")
print("\n=== role_permissions ===")
print(stdout.read().decode())
print(stderr.read().decode())

# 检�?sys_role_permission 数据
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT * FROM sys_role_permission LIMIT 10;'")
print("\n=== sys_role_permission ===")
print(stdout.read().decode())
print(stderr.read().decode())

client.close()
