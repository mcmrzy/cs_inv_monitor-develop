import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

print("=== 修复 users 表：添加 email �?===\n")

# 添加 email �?
cmd = "echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c \"ALTER TABLE users ADD COLUMN IF NOT EXISTS email VARCHAR(100);\""
stdin, stdout, stderr = client.exec_command(cmd)
print("添加 email �?")
print(stdout.read().decode())
print(stderr.read().decode())

# 创建 email 索引
cmd = "echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c \"CREATE INDEX IF NOT EXISTS idx_users_email_col ON users(email) WHERE deleted_at IS NULL;\""
stdin, stdout, stderr = client.exec_command(cmd)
print("创建 email 索引:")
print(stdout.read().decode())

# 验证
cmd = "echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c \"SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'email';\""
stdin, stdout, stderr = client.exec_command(cmd)
print("\n验证 email �?")
print(stdout.read().decode())

# 测试查询
cmd = "echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c \"SELECT id, phone, email FROM users LIMIT 3;\""
stdin, stdout, stderr = client.exec_command(cmd)
print("查询用户:")
print(stdout.read().decode())

client.close()
print("\n=== 完成 ===")
print("请刷新浏览器重新测试发送验证码")
