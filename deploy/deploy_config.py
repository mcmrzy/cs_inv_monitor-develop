import paramiko
from scp import SCPClient
import subprocess
import time
import os

LOCAL_PATH = r'd:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop'
REMOTE_DIR = '/opt/inv-mqtt'

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

print("=== 部署系统配置功能 ===\n")

# 1. 上传后端代码
print("[1/5] 上传 API Server 代码...")
with SCPClient(client.get_transport()) as scp:
    scp.put(os.path.join(LOCAL_PATH, 'inv_api_server'), recursive=True, remote_path=REMOTE_DIR)
print("  Done")

# 2. 打包前端（排除 node_modules）
print("\n[2/5] 打包前端代码...")
tar_file = os.path.join(LOCAL_PATH, 'deploy', 'frontend.tar.gz')
subprocess.run(['tar', '-czf', tar_file, '--exclude=node_modules', '--exclude=dist', '-C', LOCAL_PATH, 'inv-admin-frontend'], capture_output=True)

# 3. 上传并解压前端
print("[3/5] 上传前端代码...")
with SCPClient(client.get_transport()) as scp:
    scp.put(tar_file, remote_path='/tmp/frontend.tar.gz')
client.exec_command(f"echo 'cskj9527' | sudo -S bash -c 'cd {REMOTE_DIR} && tar -xzf /tmp/frontend.tar.gz && rm /tmp/frontend.tar.gz'")
print("  Done")

# 4. 构建部署
print("\n[4/5] 构建并部署...")
cmd = f"echo 'cskj9527' | sudo -S bash -c 'cd {REMOTE_DIR}/deploy && docker compose up -d --build'"
stdin, stdout, stderr = client.exec_command(cmd, timeout=600)
out = stdout.read().decode()
for line in out.split('\n'):
    if any(k in line.lower() for k in ['started', 'error', 'built', 'recreated', 'running']):
        print(f"  {line.strip()}")

# 5. 验证
print("\n[5/5] 验证...")
time.sleep(40)
stdin, stdout, stderr = client.exec_command(
    "echo 'cskj9527' | sudo -S docker ps --format '{{.Names}}: {{.Status}}' | grep inv"
)
print(f"\n服务状态:\n{stdout.read().decode()}")

# 清理
os.remove(tar_file)
client.close()

print("=== 部署完成 ===")
print("\n系统配置页面现在包含:")
print("  - 基本设置（站点名称）")
print("  - 邮件服务器配置（SMTP服务器/端口/用户名/密码/发件人/SSL）")
print("  - MQTT配置（Broker/端口/用户名/密码/TLS）")
print("  - 短信配置（Access Key/Secret Key/签名/模板）")
print("  - 数据管理（保留天数/告警/登录尝试/自动升级）")
print("\n修改配置后点击保存，邮件等服务会立即使用新配置，无需重启！")
