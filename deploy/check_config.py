#!/usr/bin/env python3
"""检查并修复 Docker 部署"""

import paramiko

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

# 检查 docker-compose.yml 文件
print('=== docker-compose.yml 内容 ===')
stdin, stdout, stderr = client.exec_command('cat /opt/inv-mqtt/deploy/docker-compose.yml')
print(stdout.read().decode()[:2000])

# 检查 .env 文件
print('\n=== .env 文件内容 ===')
stdin, stdout, stderr = client.exec_command('cat /opt/inv-mqtt/deploy/.env')
print(stdout.read().decode())

# 尝试手动执行 docker compose
print('\n=== 尝试手动执行 docker compose ===')
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose config'")
print(stdout.read().decode())
print(stderr.read().decode())

client.close()
