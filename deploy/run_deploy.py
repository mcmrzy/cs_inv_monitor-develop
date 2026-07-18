#!/usr/bin/env python3
"""执行 Docker 部署"""

import paramiko
import time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 执行 docker-compose 部署
print('正在启动 Docker 服务...')
cmd = "echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose down && docker compose up -d --build'"
stdin, stdout, stderr = client.exec_command(cmd, timeout=300)
print(stdout.read().decode())
err = stderr.read().decode()
if err:
    print(f'输出: {err}')

# 等待服务启动
print('\n等待服务启动...')
time.sleep(30)

# 检查服务状�?
print('\n=== 服务状�?===')
stdin, stdout, stderr = client.exec_command('docker ps')
print(stdout.read().decode())

client.close()
print('\n�?部署完成�?)
print('API 网关: http://example.invalid:8888')
print('管理后台: http://example.invalid:3000')
