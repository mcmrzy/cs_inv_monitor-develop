import paramiko
from scp import SCPClient
import os
import time

LOCAL_PATH = r'd:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop'
REMOTE_DIR = '/opt/inv-mqtt'

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='REDACTED_ROTATE_CREDENTIAL')

print("=== 推送最新代码到服务器 ===\n")

# 上传修改的文件
files_to_upload = [
    ('inv_api_server', True),  # directory
    ('inv-admin-frontend', True),  # directory
    ('database', True),  # directory
    ('deploy/docker-compose.yml', False),
    ('deploy/.env', False),
]

for item, is_dir in files_to_upload:
    local_path = os.path.join(LOCAL_PATH, item)
    if not os.path.exists(local_path):
        print(f"  跳过 {item}（不存在）")
        continue
    
    print(f"[上传] {item}...")
    try:
        with SCPClient(client.get_transport()) as scp:
            if is_dir:
                scp.put(local_path, recursive=True, remote_path=REMOTE_DIR)
            else:
                scp.put(local_path, remote_path=f"{REMOTE_DIR}/{item}")
        print(f"  Done")
    except Exception as e:
        print(f"  错误: {e}")

# 重新构建并部署
print("\n[构建] 重新构建所有服务...")
cmd = f"echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S bash -c 'cd {REMOTE_DIR}/deploy && docker compose up -d --build'"
stdin, stdout, stderr = client.exec_command(cmd, timeout=600)
out = stdout.read().decode()
for line in out.split('\n'):
    if any(k in line.lower() for k in ['started', 'error', 'built', 'recreated']):
        print(f"  {line.strip()}")

# 等待
print("\n等待服务启动...")
time.sleep(40)

# 检查状态
stdin, stdout, stderr = client.exec_command(
    "echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S docker ps --format '{{.Names}}: {{.Status}}' | grep inv"
)
print(f"\n服务状态:\n{stdout.read().decode()}")

client.close()
print("=== 推送完成 ===")
