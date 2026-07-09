import paramiko
from scp import SCPClient
import time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

DUMP_FILE = r'd:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop\deploy\inv_mqtt_dump.sql'

# 1. 上传 dump 文件
print("[1/4] 上传数据库备份...")
with SCPClient(client.get_transport()) as scp:
    scp.put(DUMP_FILE, remote_path='/tmp/inv_mqtt_dump.sql')
print("  Done")

# 2. 停止 API 服务（避免写入冲突）
print("\n[2/4] 停止 API 服务...")
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose stop inv-api-server inv-api-gateway inv-device-server'")
print(stdout.read().decode())

# 3. 恢复数据库
print("[3/4] 恢复数据库...")
# 先删除旧数据库并重建
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec inv-postgres psql -U postgres -c \"DROP DATABASE IF EXISTS inv_mqtt; CREATE DATABASE inv_mqtt OWNER postgres;\"")
print(stdout.read().decode())

# 导入数据
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec -i inv-postgres psql -U postgres -d inv_mqtt < /tmp/inv_mqtt_dump.sql")
out = stdout.read().decode()
err = stderr.read().decode()
if out: print(f"  输出: {out[:500]}")
if err and 'sudo' not in err: print(f"  错误: {err[:500]}")

# 4. 重启服务
print("\n[4/4] 重启服务...")
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose up -d'")
print(stdout.read().decode())

# 等待启动
time.sleep(30)

# 检查状态
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker ps --format 'table {{.Names}}\t{{.Status}}' | grep inv")
print(f"\n服务状态:\n{stdout.read().decode()}")

# 清理
client.exec_command("rm -f /tmp/inv_mqtt_dump.sql")

client.close()
print("\n=== 完成 ===")
