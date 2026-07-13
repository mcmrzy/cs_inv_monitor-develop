import paramiko
from scp import SCPClient
import time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='REDACTED_ROTATE_CREDENTIAL')

print("=== 重新推送数据库 ===\n")

# 1. 重新导出（使用 INSERT 语句格式，更可靠）
print("[1/5] 重新导出本地数据库...")
import subprocess
result = subprocess.run([
    'docker', 'exec', 'inv-postgres', 'pg_dump',
    '-U', 'postgres', '-d', 'inv_mqtt',
    '--no-owner', '--no-acl',
    '--inserts',  # 使用 INSERT 语句
    '-f', '/tmp/inv_mqtt_v2.sql'
], capture_output=True, text=True)
print(f"  导出: {result.stdout or 'OK'}")

# 2. 复制到本地
print("\n[2/5] 复制到本地...")
result = subprocess.run([
    'docker', 'cp', 'inv-postgres:/tmp/inv_mqtt_v2.sql',
    r'd:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop\deploy\inv_mqtt_v2.sql'
], capture_output=True, text=True)
print(f"  复制: {'OK' if result.returncode == 0 else result.stderr}")

# 3. 上传到服务器
print("\n[3/5] 上传到服务器...")
with SCPClient(client.get_transport()) as scp:
    scp.put(r'd:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop\deploy\inv_mqtt_v2.sql', remote_path='/tmp/inv_mqtt_v2.sql')
print("  Done")

# 4. 恢复数据库
print("\n[4/5] 恢复数据库...")
# 停止服务
client.exec_command("echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose stop inv-api-server inv-api-gateway inv-device-server'")

# 删除旧数据库
stdin, stdout, stderr = client.exec_command("echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -c \"DROP DATABASE IF EXISTS inv_mqtt; CREATE DATABASE inv_mqtt OWNER postgres;\"")
print(f"  重建数据库: {stdout.read().decode().strip()}")

# 导入数据
stdin, stdout, stderr = client.exec_command("echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S docker exec -i inv-postgres psql -U postgres -d inv_mqtt < /tmp/inv_mqtt_v2.sql")
out = stdout.read().decode().strip()
err = stderr.read().decode().strip()
if out: print(f"  导入输出: {out[:300]}")
if err and 'sudo' not in err: print(f"  导入错误: {err[:300]}")

# 5. 验证并重启
print("\n[5/5] 验证并重启...")
stdin, stdout, stderr = client.exec_command("echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT id, phone, email FROM users;'")
print(f"  用户数据:\n{stdout.read().decode()}")

# 重启服务
stdin, stdout, stderr = client.exec_command("echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose up -d'")
print(f"  重启: {stdout.read().decode()[:200]}")

time.sleep(30)

# 检查状态
stdin, stdout, stderr = client.exec_command("echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S docker ps --format '{{.Names}}: {{.Status}}' | grep inv")
print(f"\n服务状态:\n{stdout.read().decode()}")

client.close()
print("\n=== 完成 ===")
