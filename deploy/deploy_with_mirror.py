#!/usr/bin/env python3
"""配置 Docker 镜像并部署"""

import paramiko
import time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

# 1. 拉取镜像
print('拉取 Docker 镜像...')
images = [
    'registry.cn-hangzhou.aliyuncs.com/library/postgres:16-alpine',
    'registry.cn-hangzhou.aliyuncs.com/library/redis:7-alpine'
]

for img in images:
    print(f'拉取 {img}...')
    stdin, stdout, stderr = client.exec_command(f'docker pull {img}')
    print(stdout.read().decode())

# 2. 重新标记镜像
print('\n重新标记镜像...')
client.exec_command('docker tag registry.cn-hangzhou.aliyuncs.com/library/postgres:16-alpine postgres:16-alpine')
client.exec_command('docker tag registry.cn-hangzhou.aliyuncs.com/library/redis:7-alpine redis:7-alpine')

# 3. 执行部署
print('\n启动 Docker 服务...')
cmd = "echo 'cskj9527' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose down && docker compose up -d --build'"
stdin, stdout, stderr = client.exec_command(cmd, timeout=300)
print(stdout.read().decode())

# 4. 等待服务启动
print('\n等待服务启动...')
time.sleep(30)

# 5. 检查状态
print('\n=== 服务状态 ===')
stdin, stdout, stderr = client.exec_command('docker ps')
print(stdout.read().decode())

client.close()
print('\n✓ 部署完成！')
print('API 网关: http://192.168.8.50:8888')
print('管理后台: http://192.168.8.50:3000')
