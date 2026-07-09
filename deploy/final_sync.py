import paramiko
from scp import SCPClient
import subprocess
import time

LOCAL_PATH = r'd:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop'

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

print("=== 完整数据库同步 ===\n")

# 1. 导出本地数据库
print("[1/5] 导出本地数据库...")
result = subprocess.run([
    'docker', 'exec', 'inv-postgres', 'pg_dump',
    '-U', 'postgres', '-d', 'inv_mqtt',
    '--no-owner', '--no-acl', '-Fc',
    '-f', '/tmp/sync.dump'
], capture_output=True, text=True)
print(f"  {'OK' if result.returncode == 0 else 'ERROR: ' + result.stderr}")

# 2. 复制到本地
print("[2/5] 复制到本地...")
result = subprocess.run([
    'docker', 'cp', 'inv-postgres:/tmp/sync.dump',
    LOCAL_PATH + r'\deploy\sync.dump'
], capture_output=True, text=True)
print(f"  {'OK' if result.returncode == 0 else 'ERROR'}")

# 3. 上传到服务器
print("[3/5] 上传到服务器...")
with SCPClient(client.get_transport()) as scp:
    scp.put(LOCAL_PATH + r'\deploy\sync.dump', remote_path='/tmp/sync.dump')
print("  Done")

# 4. 停止服务、重建数据库、恢复
print("[4/5] 恢复数据库...")
stdin, stdout, stderr = client.exec_command(
    "echo 'cskj9527' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose stop inv-api-server inv-api-gateway inv-device-server'"
)
stdout.read()

stdin, stdout, stderr = client.exec_command(
    "echo 'cskj9527' | sudo -S docker exec inv-postgres psql -U postgres -c \"DROP DATABASE IF EXISTS inv_mqtt; CREATE DATABASE inv_mqtt OWNER postgres;\""
)
stdout.read()

stdin, stdout, stderr = client.exec_command(
    "echo 'cskj9527' | sudo -S docker cp /tmp/sync.dump inv-postgres:/tmp/sync.dump"
)
stdout.read()

stdin, stdout, stderr = client.exec_command(
    "echo 'cskj9527' | sudo -S docker exec inv-postgres pg_restore -U postgres -d inv_mqtt --no-owner --no-acl --clean --if-exists /tmp/sync.dump"
)
stdout.read()
stderr_out = stderr.read().decode()
errors = [l for l in stderr_out.split('\n') if 'ERROR' in l and 'sudo' not in l]
print(f"  {'OK' if not errors else f'{len(errors)} 个错误'}")

# 5. 验证
print("[5/5] 验证并重启...")
tables = ['users', 'sys_permission', 'sys_role_permission', 'device_models', 'devices']
for t in tables:
    stdin, stdout, stderr = client.exec_command(
        f"echo 'cskj9527' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -t -c 'SELECT COUNT(*) FROM {t};'"
    )
    print(f"  {t}: {stdout.read().decode().strip()} 条")

# 重启
stdin, stdout, stderr = client.exec_command(
    "echo 'cskj9527' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose up -d'"
)
stdout.read()
time.sleep(30)

stdin, stdout, stderr = client.exec_command(
    "echo 'cskj9527' | sudo -S docker ps --format '{{.Names}}: {{.Status}}' | grep inv"
)
print(f"\n服务状态:\n{stdout.read().decode()}")

client.exec_command("rm -f /tmp/sync.dump")
client.close()
print("=== 完成 ===")
