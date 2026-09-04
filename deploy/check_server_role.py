import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 检查服务器�?role_permissions
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT role, resource, action, is_allowed FROM role_permissions WHERE role = 3 ORDER BY resource;'")
print("=== 服务器角�?�?role_permissions ===")
print(stdout.read().decode())

# 检查总数
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT COUNT(*) FROM role_permissions;'")
print("=== 总数 ===")
print(stdout.read().decode())

client.close()
