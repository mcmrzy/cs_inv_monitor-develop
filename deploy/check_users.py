import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 查看所有用�?
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT id, phone, email, role, LEFT(password_hash, 20) as pwd_prefix FROM users;'")
print("=== 用户列表 ===")
print(stdout.read().decode())

# 查看各角色的权限
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT DISTINCT role_id FROM sys_role_permission ORDER BY role_id;'")
print("=== 有权限的角色 ===")
print(stdout.read().decode())

# 查看角色3的权�?
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c \"SELECT sp.resource, sp.action FROM sys_role_permission srp JOIN sys_permission sp ON srp.permission_id = sp.id WHERE srp.role_id = 3 ORDER BY sp.resource;\"")
print("\n=== 角色3的权�?===")
print(stdout.read().decode())

# 查看角色0的权�?
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c \"SELECT sp.resource, sp.action FROM sys_role_permission srp JOIN sys_permission sp ON srp.permission_id = sp.id WHERE srp.role_id = 0 ORDER BY sp.resource;\"")
print("\n=== 角色0的权�?===")
print(stdout.read().decode() or "  (无权�?")

client.close()
