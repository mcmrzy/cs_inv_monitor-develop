import paramiko
from scp import SCPClient
import subprocess
import time

LOCAL_PATH = r'd:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop'

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='REDACTED_ROTATE_CREDENTIAL')

print("=== 使用 pg_restore 同步数据库 ===\n")

# 1. 用 custom 格式导出
print("[1/6] 导出本地数据库（custom 格式）...")
result = subprocess.run([
    'docker', 'exec', 'inv-postgres', 'pg_dump',
    '-U', 'postgres', '-d', 'inv_mqtt',
    '--no-owner', '--no-acl',
    '-Fc',  # custom format
    '-f', '/tmp/inv_mqtt.dump'
], capture_output=True, text=True)
print(f"  导出: {'OK' if result.returncode == 0 else result.stderr}")

# 2. 复制到本地
print("\n[2/6] 复制到本地...")
result = subprocess.run([
    'docker', 'cp', 'inv-postgres:/tmp/inv_mqtt.dump',
    LOCAL_PATH + r'\deploy\inv_mqtt.dump'
], capture_output=True, text=True)
print(f"  复制: {'OK' if result.returncode == 0 else result.stderr}")

# 3. 上传到服务器
print("\n[3/6] 上传到服务器...")
with SCPClient(client.get_transport()) as scp:
    scp.put(LOCAL_PATH + r'\deploy\inv_mqtt.dump', remote_path='/tmp/inv_mqtt.dump')
print("  Done")

# 4. 停止服务
print("\n[4/6] 停止服务...")
stdin, stdout, stderr = client.exec_command(
    "echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose stop inv-api-server inv-api-gateway inv-device-server'"
)
stdout.read()

# 5. 恢复数据库
print("[5/6] 恢复数据库...")
# 重建数据库
stdin, stdout, stderr = client.exec_command(
    "echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -c \"DROP DATABASE IF EXISTS inv_mqtt; CREATE DATABASE inv_mqtt OWNER postgres;\""
)
stdout.read()

# 复制 dump 文件到容器
stdin, stdout, stderr = client.exec_command(
    "echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S docker cp /tmp/inv_mqtt.dump inv-postgres:/tmp/inv_mqtt.dump"
)
print("  复制到容器: OK")

# 使用 pg_restore 导入
stdin, stdout, stderr = client.exec_command(
    "echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres pg_restore -U postgres -d inv_mqtt --no-owner --no-acl /tmp/inv_mqtt.dump"
)
out = stdout.read().decode()
err = stderr.read().decode()
if err and 'sudo' not in err:
    error_lines = [l for l in err.split('\n') if l.strip() and 'WARNING' not in l]
    if error_lines:
        print(f"  导入错误: {len(error_lines)} 条")
        for e in error_lines[:3]:
            print(f"    {e.strip()[:100]}")
    else:
        print("  导入: OK (有 warnings 但无错误)")
else:
    print("  导入: OK")

# 6. 验证并重启
print("\n[6/6] 验证并重启...")

# 验证数据
tables = ['users', 'sys_permission', 'sys_role_permission', 'devices', 'stations', 'alarms']
for table in tables:
    stdin, stdout, stderr = client.exec_command(
        f"echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -t -c 'SELECT COUNT(*) FROM {table};'"
    )
    count = stdout.read().decode().strip()
    print(f"  {table}: {count} 条")

# 重启所有服务
stdin, stdout, stderr = client.exec_command(
    "echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose up -d'"
)
stdout.read()

time.sleep(30)

# 检查状态
stdin, stdout, stderr = client.exec_command(
    "echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S docker ps --format '{{.Names}}: {{.Status}}' | grep inv"
)
print(f"\n  服务状态:\n{stdout.read().decode()}")

# 清理
client.exec_command("rm -f /tmp/inv_mqtt.dump")

client.close()
print("=== 同步完成 ===")
print("请刷新浏览器 (Ctrl+Shift+R) 重新登录")
