#!/usr/bin/env python3
"""检查并从 Harbor 拉取镜像"""

import paramiko
import time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

# 检查本地镜像
print('=== 本地 Docker 镜像 ===')
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker images")
print(stdout.read().decode())

# 从 Harbor 拉取镜像
print('\n=== 从 Harbor 拉取镜像 ===')
harbor_images = [
    '192.168.8.50:4431/library/postgres:16-alpine',
    '192.168.8.50:4431/library/redis:7-alpine'
]

for img in harbor_images:
    print(f'拉取 {img}...')
    stdin, stdout, stderr = client.exec_command(f"echo 'cskj9527' | sudo -S docker pull {img}")
    print(stdout.read().decode())
    print(stderr.read().decode())

# 重新标记镜像
print('\n重新标记镜像...')
client.exec_command("echo 'cskj9527' | sudo -S docker tag 192.168.8.50:4431/library/postgres:16-alpine postgres:16-alpine")
client.exec_command("echo 'cskj9527' | sudo -S docker tag 192.168.8.50:4431/library/redis:7-alpine redis:7-alpine")

# 执行部署
print('\n开始部署...')
cmd = "echo 'cskj9527' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose up -d --build'"
stdin, stdout, stderr = client.exec_command(cmd, timeout=300)
print(stdout.read().decode())
print(stderr.read().decode())

# 等待服务启动
print('\n等待服务启动...')
time.sleep(30)

# 检查服务状态
print('\n=== 服务状态 ===')
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker ps")
print(stdout.read().decode())

client.close()
print('\n✓ 部署完成！')
print('API 网关: http://192.168.8.50:8888')
print('管理后台: http://192.168.8.50:3000')
