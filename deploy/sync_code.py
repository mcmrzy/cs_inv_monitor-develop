import paramiko
from scp import SCPClient
import os
import time

LOCAL_PATH = r'd:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop'
REMOTE_DIR = '/opt/inv-mqtt'

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

print("=== 同步最新代码到服务�?===\n")

# 需要同步的目录（排�?node_modules �?bin 等大目录�?
sync_dirs = [
    'inv_api_server',
    'inv_device_server', 
    'api-gateway',
    'inv-admin-frontend',
    'database',
]

for dir_name in sync_dirs:
    local_dir = os.path.join(LOCAL_PATH, dir_name)
    if not os.path.exists(local_dir):
        print(f"  跳过 {dir_name}（不存在�?)
        continue
    
    print(f"[上传] {dir_name}...")
    try:
        with SCPClient(client.get_transport()) as scp:
            scp.put(local_dir, recursive=True, remote_path=REMOTE_DIR)
        print(f"  Done")
    except Exception as e:
        print(f"  错误: {e}")

# 上传 deploy 目录中的关键文件
print("\n[上传] deploy 配置文件...")
deploy_files = ['docker-compose.yml', '.env']
sftp = client.open_sftp()
for f in deploy_files:
    local_file = os.path.join(LOCAL_PATH, 'deploy', f)
    remote_file = f"{REMOTE_DIR}/deploy/{f}"
    if os.path.exists(local_file):
        try:
            sftp.put(local_file, remote_file)
            print(f"  {f}: OK")
        except Exception as e:
            print(f"  {f}: {e}")
sftp.close()

# 重新构建并部�?
print("\n[构建] 重新构建所有服�?..")
cmd = f"echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S bash -c 'cd {REMOTE_DIR}/deploy && docker compose down && docker compose up -d --build'"
stdin, stdout, stderr = client.exec_command(cmd, timeout=600)
out = stdout.read().decode()
# 只打印关键信�?
for line in out.split('\n'):
    if any(k in line.lower() for k in ['started', 'error', 'built', 'recreated']):
        print(f"  {line.strip()}")

# 等待启动
print("\n等待服务启动...")
time.sleep(40)

# 检查状�?
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker ps --format 'table {{.Names}}\t{{.Status}}' | grep inv")
print(f"\n服务状�?\n{stdout.read().decode()}")

client.close()
print("=== 同步完成 ===")
