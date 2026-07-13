import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='REDACTED_ROTATE_CREDENTIAL')

# 检查 role_permissions 表
stdin, stdout, stderr = client.exec_command("echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT COUNT(*) FROM role_permissions;'")
print("=== role_permissions 表数据量 ===")
print(stdout.read().decode())

# 查看本地的 role_permissions 数据
import subprocess
result = subprocess.run([
    'docker', 'exec', 'inv-postgres', 'psql', '-U', 'postgres', '-d', 'inv_mqtt',
    '-t', '-A', '-c', "SELECT role, resource, action, is_allowed FROM role_permissions WHERE role = 3 ORDER BY resource;"
], capture_output=True, text=True)
print("=== 本地角色3的 role_permissions ===")
print(result.stdout[:1000])

client.close()
