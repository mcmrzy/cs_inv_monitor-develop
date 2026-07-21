import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 检�?users 表数�?
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT id, phone, email, nickname FROM users LIMIT 5;'")
print("=== users 表数�?===")
print(stdout.read().decode())
print(stderr.read().decode())

# 检查表数量
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c '\\dt' | wc -l")
print(f"\n表数�? {stdout.read().decode().strip()}")

client.close()
