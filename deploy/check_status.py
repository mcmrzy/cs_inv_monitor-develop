#!/usr/bin/env python3
"""检查 Docker 服务状态"""

import paramiko

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

# 使用 sudo 检查 Docker 容器状态
print('=== Docker 容器状态 ===')
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker ps -a")
print(stdout.read().decode())
err = stderr.read().decode()
if err and 'sudo' not in err:
    print(f'错误: {err}')

# 检查服务日志
print('\n=== API 服务日志 (最后20行) ===')
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker logs inv-api-server --tail 20 2>&1")
print(stdout.read().decode())

client.close()
