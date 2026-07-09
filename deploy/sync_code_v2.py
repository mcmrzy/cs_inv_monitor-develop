import paramiko
from scp import SCPClient
import os
import time
import subprocess

LOCAL_PATH = r'd:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop'
REMOTE_DIR = '/opt/inv-mqtt'

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

print("=== 同步代码（排除 node_modules）===\n")

# 1. 上传 Go 后端服务（已经上传完成，跳过）
print("[1/6] 后端代码已上传，跳过")

# 2. 使用 tar 方式上传前端（排除 node_modules）
print("\n[2/6] 打包前端代码（排除 node_modules）...")
tar_file = os.path.join(LOCAL_PATH, 'deploy', 'frontend.tar.gz')
result = subprocess.run([
    'tar', '-czf', tar_file,
    '--exclude=node_modules',
    '--exclude=dist',
    '-C', LOCAL_PATH, 'inv-admin-frontend'
], capture_output=True, text=True, cwd=LOCAL_PATH)
print(f"  打包: {'OK' if result.returncode == 0 else result.stderr}")

# 上传 tar 文件
print("\n[3/6] 上传前端代码...")
with SCPClient(client.get_transport()) as scp:
    scp.put(tar_file, remote_path='/tmp/frontend.tar.gz')
print("  Done")

# 解压到服务器
print("\n[4/6] 解压前端代码...")
stdin, stdout, stderr = client.exec_command(f"echo 'cskj9527' | sudo -S bash -c 'cd {REMOTE_DIR} && tar -xzf /tmp/frontend.tar.gz && rm /tmp/frontend.tar.gz'")
print(stdout.read().decode().strip() or "OK")

# 上传 deploy 配置
print("\n[5/6] 上传 deploy 配置...")
sftp = client.open_sftp()
for f in ['docker-compose.yml', '.env']:
    local_file = os.path.join(LOCAL_PATH, 'deploy', f)
    if os.path.exists(local_file):
        sftp.put(local_file, f"{REMOTE_DIR}/deploy/{f}")
        print(f"  {f}: OK")
sftp.close()

# 重新构建并部署
print("\n[6/6] 重新构建并部署...")
cmd = f"echo 'cskj9527' | sudo -S bash -c 'cd {REMOTE_DIR}/deploy && docker compose up -d --build'"
stdin, stdout, stderr = client.exec_command(cmd, timeout=600)
out = stdout.read().decode()
for line in out.split('\n'):
    if any(k in line.lower() for k in ['started', 'error', 'built', 'recreated', 'running']):
        print(f"  {line.strip()}")

# 等待
print("\n等待服务启动...")
time.sleep(40)

# 状态检查
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker ps --format 'table {{.Names}}\t{{.Status}}' | grep inv")
print(f"\n服务状态:\n{stdout.read().decode()}")

# 清理本地 tar
os.remove(tar_file)

client.close()
print("=== 同步完成 ===")
