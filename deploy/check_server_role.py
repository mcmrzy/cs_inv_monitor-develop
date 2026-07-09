import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

# 检查服务器的 role_permissions
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT role, resource, action, is_allowed FROM role_permissions WHERE role = 3 ORDER BY resource;'")
print("=== 服务器角色3的 role_permissions ===")
print(stdout.read().decode())

# 检查总数
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT COUNT(*) FROM role_permissions;'")
print("=== 总数 ===")
print(stdout.read().decode())

client.close()
