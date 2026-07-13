import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='REDACTED_ROTATE_CREDENTIAL')

print("=== 修复 users 表 ===\n")

sql = """
ALTER TABLE users ADD COLUMN IF NOT EXISTS email VARCHAR(100);
ALTER TABLE users ADD COLUMN IF NOT EXISTS parent_id BIGINT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS timezone VARCHAR(50) DEFAULT 'Asia/Shanghai';
CREATE INDEX IF NOT EXISTS idx_users_email_col ON users(email) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_users_parent ON users(parent_id);
"""

cmd = f"echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c \"{sql}\""
stdin, stdout, stderr = client.exec_command(cmd)
print(stdout.read().decode())

# 验证
cmd = "echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c '\\d users'"
stdin, stdout, stderr = client.exec_command(cmd)
print("=== 修复后的 users 表 ===")
print(stdout.read().decode())

client.close()
