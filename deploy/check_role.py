import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 查看角色3的权�?
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c \"SELECT sp.resource, sp.action FROM sys_role_permission srp JOIN sys_permission sp ON srp.permission_id = sp.id WHERE srp.role_id = 3 ORDER BY sp.resource;\"")
print("=== 角色3的权�?===")
print(stdout.read().decode())

# 查看用户的登录信�?
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT id, phone, role FROM users;'")
print("=== 用户信息 ===")
print(stdout.read().decode())

client.close()
