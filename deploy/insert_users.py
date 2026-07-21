import paramiko
import time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

print("=== 直接插入用户数据 ===\n")

# 从本地获取用户数�?
import subprocess
result = subprocess.run([
    'docker', 'exec', 'inv-postgres', 'psql', '-U', 'postgres', '-d', 'inv_mqtt',
    '-t', '-A', '-c',
    "SELECT id, phone, email, password_hash, nickname, avatar, role, status FROM users;"
], capture_output=True, text=True)

users_data = result.stdout.strip()
print(f"本地用户数据:\n{users_data}\n")

# 为每个用户生�?INSERT 语句
for line in users_data.split('\n'):
    if not line.strip():
        continue
    parts = line.split('|')
    if len(parts) >= 8:
        uid, phone, email, pwd_hash, nickname, avatar, role, status = parts[:8]
        # 转义单引�?
        email_escaped = email.replace("'", "''")
        pwd_hash_escaped = pwd_hash.replace("'", "''")
        nickname_escaped = nickname.replace("'", "''")
        avatar_escaped = avatar.replace("'", "''")
        
        sql = f"""INSERT INTO users (id, phone, email, password_hash, nickname, avatar, role, status) 
VALUES ({uid}, '{phone}', '{email_escaped}', '{pwd_hash_escaped}', '{nickname_escaped}', '{avatar_escaped}', {role}, {status}) 
ON CONFLICT (phone) DO UPDATE SET email = EXCLUDED.email, password_hash = EXCLUDED.password_hash, nickname = EXCLUDED.nickname;"""
        
        cmd = f"echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c \"{sql}\""
        stdin, stdout, stderr = client.exec_command(cmd)
        out = stdout.read().decode().strip()
        err = stderr.read().decode().strip()
        print(f"  用户 {phone}: {out or 'OK'}")
        if err and 'sudo' not in err:
            print(f"    错误: {err}")

# 重置序列
client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c \"SELECT setval('users_id_seq', (SELECT COALESCE(MAX(id), 1) FROM users));\"")

# 验证
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT id, phone, email, nickname FROM users;'")
print(f"\n验证:\n{stdout.read().decode()}")

# 重启服务
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose up -d'")
print(f"重启: {stdout.read().decode()[:200]}")

time.sleep(20)

client.close()
print("\n=== 完成 ===")
print("请刷新浏览器重新登录")
