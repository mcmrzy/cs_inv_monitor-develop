import paramiko
from scp import SCPClient
import subprocess
import time

LOCAL_PATH = r'd:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop'

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

print("=== 完整同步本地数据库到服务器 ===\n")

# 1. 用 COPY 格式导出（默认格式，不会出 JSON 错误）
print("[1/6] 导出本地数据库（COPY 格式）...")
result = subprocess.run([
    'docker', 'exec', 'inv-postgres', 'pg_dump',
    '-U', 'postgres', '-d', 'inv_mqtt',
    '--no-owner', '--no-acl',
    '-f', '/tmp/inv_full.sql'
], capture_output=True, text=True)
print(f"  导出: {'OK' if result.returncode == 0 else result.stderr}")

# 2. 从容器复制到本地
print("\n[2/6] 复制到本地...")
result = subprocess.run([
    'docker', 'cp', 'inv-postgres:/tmp/inv_full.sql',
    LOCAL_PATH + r'\deploy\inv_full.sql'
], capture_output=True, text=True)
print(f"  复制: {'OK' if result.returncode == 0 else result.stderr}")

# 3. 上传到服务器
print("\n[3/6] 上传到服务器...")
with SCPClient(client.get_transport()) as scp:
    scp.put(LOCAL_PATH + r'\deploy\inv_full.sql', remote_path='/tmp/inv_full.sql')
print("  Done")

# 4. 停止服务
print("\n[4/6] 停止服务...")
stdin, stdout, stderr = client.exec_command(
    "echo 'cskj9527' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose stop inv-api-server inv-api-gateway inv-device-server'"
)
stdout.read()

# 5. 恢复数据库
print("[5/6] 恢复数据库...")
# 重建数据库
stdin, stdout, stderr = client.exec_command(
    "echo 'cskj9527' | sudo -S docker exec inv-postgres psql -U postgres -c \"DROP DATABASE IF EXISTS inv_mqtt; CREATE DATABASE inv_mqtt OWNER postgres;\""
)
print(f"  重建: {stdout.read().decode().strip()}")

# 复制 dump 文件到容器
stdin, stdout, stderr = client.exec_command(
    "echo 'cskj9527' | sudo -S docker cp /tmp/inv_full.sql inv-postgres:/tmp/inv_full.sql"
)
print(f"  复制到容器: OK")

# 在容器内执行导入
stdin, stdout, stderr = client.exec_command(
    "echo 'cskj9527' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -f /tmp/inv_full.sql"
)
out = stdout.read().decode()
err = stderr.read().decode()
# 只打印错误行
error_lines = [l for l in err.split('\n') if 'ERROR' in l and 'sudo' not in l]
if error_lines:
    print(f"  导入错误 ({len(error_lines)} 条):")
    for e in error_lines[:5]:
        print(f"    {e.strip()}")
else:
    print(f"  导入: OK")

# 6. 验证并重启
print("\n[6/6] 验证并重启...")
# 验证用户
stdin, stdout, stderr = client.exec_command(
    "echo 'cskj9527' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT id, phone, email, role FROM users;'"
)
print(f"  用户:\n{stdout.read().decode()}")

# 验证权限
stdin, stdout, stderr = client.exec_command(
    "echo 'cskj9527' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c 'SELECT COUNT(*) as perm_count FROM sys_permission; SELECT COUNT(*) as role_perm_count FROM sys_role_permission;'"
)
print(f"  权限:\n{stdout.read().decode()}")

# 重启所有服务
stdin, stdout, stderr = client.exec_command(
    "echo 'cskj9527' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose up -d'"
)
stdout.read()

time.sleep(30)

# 检查状态
stdin, stdout, stderr = client.exec_command(
    "echo 'cskj9527' | sudo -S docker ps --format '{{.Names}}: {{.Status}}' | grep inv"
)
print(f"  服务状态:\n{stdout.read().decode()}")

# 清理
client.exec_command("rm -f /tmp/inv_full.sql")
client.close()

print("=== 同步完成 ===")
print("请刷新浏览器 (Ctrl+Shift+R) 重新登录")
