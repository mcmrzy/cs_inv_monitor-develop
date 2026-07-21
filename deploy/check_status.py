#!/usr/bin/env python3
"""检�?Docker 服务状�?""

import paramiko

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 使用 sudo 检�?Docker 容器状�?
print('=== Docker 容器状�?===')
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker ps -a")
print(stdout.read().decode())
err = stderr.read().decode()
if err and 'sudo' not in err:
    print(f'错误: {err}')

# 检查服务日�?
print('\n=== API 服务日志 (最�?0�? ===')
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker logs inv-api-server --tail 20 2>&1")
print(stdout.read().decode())

client.close()
