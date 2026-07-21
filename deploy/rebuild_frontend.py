import paramiko
from scp import SCPClient
import os
import time

LOCAL_PATH = r'd:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop'

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

print("=== 重新部署前端 ===\n")

# 上传最新前端代�?
print("[1/3] 上传最新前端代�?..")
with SCPClient(client.get_transport()) as scp:
    scp.put(os.path.join(LOCAL_PATH, 'inv-admin-frontend'), recursive=True, remote_path='/opt/inv-mqtt/')
print("  Done")

# 重新构建前端
print("\n[2/3] 重新构建前端...")
cmd = "echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose up -d --build inv-admin-frontend'"
stdin, stdout, stderr = client.exec_command(cmd, timeout=300)
output = stdout.read().decode()
# 只打印关键信�?
for line in output.split('\n'):
    if any(k in line.lower() for k in ['built', 'started', 'error', 'done', 'exporting']):
        print(f"  {line.strip()}")

# 等待启动
print("\n[3/3] 等待服务启动...")
time.sleep(20)

# 检查状�?
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker ps --format 'table {{.Names}}\t{{.Status}}' | grep inv-admin")
print(f"\n前端状�? {stdout.read().decode().strip()}")

client.close()
print("\n=== 完成 ===")
print("请刷新浏览器 (Ctrl+Shift+R) 重新测试")
