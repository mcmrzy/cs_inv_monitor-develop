#!/usr/bin/env python3
"""执行 Docker 部署"""

import paramiko
import time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

# 执行 docker-compose 部署
print('正在启动 Docker 服务...')
cmd = "echo 'cskj9527' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose down && docker compose up -d --build'"
stdin, stdout, stderr = client.exec_command(cmd, timeout=300)
print(stdout.read().decode())
err = stderr.read().decode()
if err:
    print(f'输出: {err}')

# 等待服务启动
print('\n等待服务启动...')
time.sleep(30)

# 检查服务状态
print('\n=== 服务状态 ===')
stdin, stdout, stderr = client.exec_command('docker ps')
print(stdout.read().decode())

client.close()
print('\n✓ 部署完成！')
print('API 网关: http://192.168.8.50:8888')
print('管理后台: http://192.168.8.50:3000')
