import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

# 检查 users 表数据
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT id, phone, email, nickname FROM users LIMIT 5;'")
print("=== users 表数据 ===")
print(stdout.read().decode())
print(stderr.read().decode())

# 检查表数量
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c '\\dt' | wc -l")
print(f"\n表数量: {stdout.read().decode().strip()}")

client.close()
