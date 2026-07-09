#!/usr/bin/env python3
"""上传代码并部署"""

import paramiko
from scp import SCPClient
import os

SERVER = '192.168.8.50'
USERNAME = 'cskj'
PASSWORD = 'cskj9527'
REMOTE_DIR = '/opt/inv-mqtt'
LOCAL_PATH = r'd:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop'

# 连接服务器
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(SERVER, username=USERNAME, password=PASSWORD)
print('✓ 连接成功')

# 1. 写入 .env 文件
print('\n[1/5] 写入 .env 文件...')
env_content = """DB_HOST=postgres
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=InvMonitor@2026!Secure
DB_NAME=inv_mqtt
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=RCq/G7b4T00dt5bprW7o34c/OOgPHPKe55Iwz3GvQYQ=
JWT_SECRET=fq2T9il2RpZpSmUH1pLbV4cIwaEWypg3wjT629+GPeassiiW6A+wXdC+4jennVyN
API_SERVER_URL=http://inv-api-server:8080
DEVICE_SERVER_URL=http://inv-device-server:8081
INTERNAL_KEY=inv-monitor-internal-secret-2026
MQTT_BROKER=jiuxiaoyw.online
MQTT_PORT=8883
MQTT_CLIENT_ID=CSKJ-INV-SERVER-DEVICE-LOCAL
MQTT_USERNAME=CSKJ-INV-SERVER-DEVICE
MQTT_PASSWORD=CSKJINVSERVERDEVICE
MQTT_TLS_INSECURE=true
EMAIL_HOST=smtp.qq.com
EMAIL_PORT=465
EMAIL_USER=sunhaoyu0221@qq.com
EMAIL_PASS=uqcomryxtnimbeha
EMAIL_FROM=sunhaoyu0221@qq.com"""

# 使用 SFTP 写入文件
sftp = client.open_sftp()
with sftp.file(f'{REMOTE_DIR}/deploy/.env', 'w') as f:
    f.write(env_content)
sftp.close()
print('✓ .env 文件已写入')

# 2. 上传 inv_api_server 目录
print('\n[2/5] 上传 inv_api_server...')
with SCPClient(client.get_transport()) as scp:
    scp.put(os.path.join(LOCAL_PATH, 'inv_api_server'), recursive=True, remote_path=REMOTE_DIR)
print('✓ inv_api_server 上传完成')

# 3. 上传 inv_device_server 目录
print('\n[3/5] 上传 inv_device_server...')
with SCPClient(client.get_transport()) as scp:
    scp.put(os.path.join(LOCAL_PATH, 'inv_device_server'), recursive=True, remote_path=REMOTE_DIR)
print('✓ inv_device_server 上传完成')

# 4. 上传 api-gateway 目录
print('\n[4/5] 上传 api-gateway...')
with SCPClient(client.get_transport()) as scp:
    scp.put(os.path.join(LOCAL_PATH, 'api-gateway'), recursive=True, remote_path=REMOTE_DIR)
print('✓ api-gateway 上传完成')

# 5. 上传 database 目录
print('\n[5/5] 上传 database...')
with SCPClient(client.get_transport()) as scp:
    scp.put(os.path.join(LOCAL_PATH, 'database'), recursive=True, remote_path=REMOTE_DIR)
print('✓ database 上传完成')

# 6. 执行部署
print('\n[6/6] 启动 Docker 服务...')
cmd = f"echo '{PASSWORD}' | sudo -S bash -c 'cd {REMOTE_DIR}/deploy && docker-compose down && docker-compose up -d --build'"
stdin, stdout, stderr = client.exec_command(cmd, timeout=300)
print(stdout.read().decode())
err = stderr.read().decode()
if err and 'sudo' not in err:
    print(f'错误: {err}')

# 7. 检查状态
print('\n[7/7] 检查服务状态...')
stdin, stdout, stderr = client.exec_command('docker ps')
print(stdout.read().decode())

client.close()
print('\n✓ 部署完成！')
print(f'API 网关: http://{SERVER}:8888')
print(f'管理后台: http://{SERVER}:3000')
