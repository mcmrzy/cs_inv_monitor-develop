#!/usr/bin/env python3
"""手动执行 Docker 部署"""

import paramiko
import time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 执行 docker compose up
print('正在启动 Docker 服务...')
cmd = "echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose up -d --build'"
stdin, stdout, stderr = client.exec_command(cmd, timeout=300)
output = stdout.read().decode()
error = stderr.read().decode()

print('=== 输出 ===')
print(output)

print('\n=== 错误 ===')
print(error)

# 等待服务启动
print('\n等待服务启动...')
time.sleep(30)

# 检查服务状�?
print('\n=== 服务状�?===')
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker ps")
print(stdout.read().decode())

client.close()
