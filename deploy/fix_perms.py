import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

print("=== 修复密码和权限 ===\n")

# 1. 修复密码哈希（补全 $2b$10$ 前缀）
print("[1/3] 修复密码哈希...")
# 先获取本地正确的密码哈希
import subprocess
result = subprocess.run([
    'docker', 'exec', 'inv-postgres', 'psql', '-U', 'postgres', '-d', 'inv_mqtt',
    '-t', '-A', '-c', "SELECT id, password_hash FROM users;"
], capture_output=True, text=True)

for line in result.stdout.strip().split('\n'):
    if not line.strip():
        continue
    parts = line.split('|')
    if len(parts) >= 2:
        uid, pwd_hash = parts[0], parts[1]
        pwd_escaped = pwd_hash.replace("'", "''")
        sql = f"UPDATE users SET password_hash = '{pwd_escaped}' WHERE id = {uid};"
        cmd = f"echo 'cskj9527' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c \"{sql}\""
        stdin, stdout, stderr = client.exec_command(cmd)
        out = stdout.read().decode().strip()
        print(f"  用户 {uid}: {out}")

# 2. 为角色 0 添加管理员权限（复制角色 1 的权限）
print("\n[2/3] 为角色 0 添加管理员权限...")
sql = "INSERT INTO sys_role_permission (role_id, permission_id) SELECT 0, permission_id FROM sys_role_permission WHERE role_id = 1 ON CONFLICT DO NOTHING;"
cmd = f"echo 'cskj9527' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c \"{sql}\""
stdin, stdout, stderr = client.exec_command(cmd)
print(f"  {stdout.read().decode().strip()}")

# 3. 验证
print("\n[3/3] 验证...")
# 验证密码
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT id, phone, LEFT(password_hash, 7) as prefix FROM users;'")
print(f"  密码前缀:\n{stdout.read().decode()}")

# 验证角色0权限
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT COUNT(*) FROM sys_role_permission WHERE role_id = 0;'")
print(f"  角色0权限数: {stdout.read().decode().strip()}")

client.close()
print("\n=== 修复完成 ===")
print("请刷新浏览器重新登录")
