import paramiko
from scp import SCPClient
import time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

print("=== 使用 docker cp 方式恢复数据库 ===\n")

# 1. 停止服务
print("[1/5] 停止服务...")
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose stop inv-api-server inv-api-gateway inv-device-server'")
print(stdout.read().decode()[:100])

# 2. 重建数据库
print("\n[2/5] 重建数据库...")
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec inv-postgres psql -U postgres -c \"DROP DATABASE IF EXISTS inv_mqtt; CREATE DATABASE inv_mqtt OWNER postgres;\"")
print(stdout.read().decode().strip())

# 3. 复制 dump 文件到容器
print("\n[3/5] 复制 dump 文件到容器...")
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker cp /tmp/inv_mqtt_v2.sql inv-postgres:/tmp/inv_mqtt_v2.sql")
print(stdout.read().decode().strip() or "OK")

# 4. 在容器内执行 psql 导入
print("\n[4/5] 导入数据...")
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -f /tmp/inv_mqtt_v2.sql")
out = stdout.read().decode()
err = stderr.read().decode()
if out: print(f"  输出: {out[:500]}")
if err and 'sudo' not in err: print(f"  错误: {err[:500]}")

# 5. 验证并重启
print("\n[5/5] 验证...")
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT id, phone, email, nickname FROM users;'")
print(f"用户数据:\n{stdout.read().decode()}")

# 重启服务
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose up -d'")
print(f"重启: {stdout.read().decode()[:200]}")

time.sleep(20)

stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker ps --format '{{.Names}}: {{.Status}}' | grep inv")
print(f"\n服务状态:\n{stdout.read().decode()}")

client.close()
print("=== 完成 ===")
