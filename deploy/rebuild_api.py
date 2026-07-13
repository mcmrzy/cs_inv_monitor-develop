import paramiko
from scp import SCPClient
import os
import time

LOCAL_PATH = r'd:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop'

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='REDACTED_ROTATE_CREDENTIAL')

print("=== 重新部署 API Server ===\n")

# 上传最新的 API Server 代码
print("[1/4] 上传最新 API Server 代码...")
with SCPClient(client.get_transport()) as scp:
    scp.put(os.path.join(LOCAL_PATH, 'inv_api_server'), recursive=True, remote_path='/opt/inv-mqtt/')
print("  Done")

# 重新构建并部署
print("\n[2/4] 重新构建 API Server...")
cmd = "echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose up -d --build inv-api-server'"
stdin, stdout, stderr = client.exec_command(cmd, timeout=300)
output = stdout.read().decode()
print(output[:500])

# 等待启动
print("\n[3/4] 等待服务启动...")
time.sleep(30)

# 检查状态
stdin, stdout, stderr = client.exec_command("echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S docker ps --format 'table {{.Names}}\t{{.Status}}' | grep inv-api")
print(f"\n[4/4] 服务状态: {stdout.read().decode().strip()}")

# 测试邮件接口
stdin, stdout, stderr = client.exec_command("""curl -s -X POST 'http://127.0.0.1:8888/api/v1/auth/send-email-code' -H 'Content-Type: application/json' -H 'X-Captcha-Token: test' -d '{"email":"test@test.com","type":"register"}'""")
print(f"\n邮件接口测试: {stdout.read().decode().strip()}")

client.close()
print("\n=== 完成 ===")
