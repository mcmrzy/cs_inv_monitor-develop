import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

# 查看角色3的权限
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c \"SELECT sp.resource, sp.action FROM sys_role_permission srp JOIN sys_permission sp ON srp.permission_id = sp.id WHERE srp.role_id = 3 ORDER BY sp.resource;\"")
print("=== 角色3的权限 ===")
print(stdout.read().decode())

# 查看用户的登录信息
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT id, phone, role FROM users;'")
print("=== 用户信息 ===")
print(stdout.read().decode())

client.close()
