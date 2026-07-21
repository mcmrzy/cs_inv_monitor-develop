import paramiko
from scp import SCPClient
import os
import time

LOCAL_PATH = r'd:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop'
REMOTE_DIR = '/opt/inv-mqtt'

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

print("=== 重新部署 API Server ===\n")

# 上传最新代�?
print("[1/3] 上传最�?API Server 代码...")
with SCPClient(client.get_transport()) as scp:
    scp.put(os.path.join(LOCAL_PATH, 'inv_api_server'), recursive=True, remote_path=REMOTE_DIR)
print("  Done")

# 重新构建
print("\n[2/3] 重新构建...")
cmd = "echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose up -d --build inv-api-server'"
stdin, stdout, stderr = client.exec_command(cmd, timeout=300)
out = stdout.read().decode()
for line in out.split('\n'):
    if any(k in line.lower() for k in ['started', 'error', 'built', 'recreated']):
        print(f"  {line.strip()}")

# 等待
print("\n[3/3] 等待启动...")
time.sleep(30)

# 检查状�?
stdin, stdout, stderr = client.exec_command(
    "echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker ps --format '{{.Names}}: {{.Status}}' | grep api"
)
print(f"\n服务状�?\n{stdout.read().decode()}")

client.close()
print("=== 完成 ===")
print("请刷新浏览器重试")
