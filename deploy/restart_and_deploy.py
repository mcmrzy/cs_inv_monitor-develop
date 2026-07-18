#!/usr/bin/env python3
"""重启 Docker 并部�?""

import paramiko
import time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 重启 Docker 服务
print('重启 Docker 服务...')
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S systemctl restart docker")
print(stdout.read().decode())
print(stderr.read().decode())

# 等待 Docker 启动
time.sleep(10)

# 检�?Docker 状�?
print('\nDocker 状�?')
stdin, stdout, stderr = client.exec_command('docker --version')
print(stdout.read().decode())

# 执行部署
print('\n开始部�?..')
cmd = "echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose up -d --build'"
stdin, stdout, stderr = client.exec_command(cmd, timeout=300)
output = stdout.read().decode()
error = stderr.read().decode()

print('\n=== 输出 ===')
print(output)
if error:
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
print('\n�?部署完成�?)
print('API 网关: http://example.invalid:8888')
print('管理后台: http://example.invalid:3000')
