import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='REDACTED_ROTATE_CREDENTIAL')

# 查看 users 表结构
stdin, stdout, stderr = client.exec_command("echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c '\\d users'")
print("=== users 表结构 ===")
print(stdout.read().decode())

client.close()
