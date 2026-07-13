#!/usr/bin/env python3
"""检查并修复 Docker 部署"""

import os
import paramiko

from secret_env import ssh_connect_kwargs, sudo_stdin_password

client = paramiko.SSHClient()
client.load_system_host_keys()
client.set_missing_host_key_policy(paramiko.RejectPolicy())
client.connect(**ssh_connect_kwargs())

# 检查 docker-compose.yml 文件
print('=== docker-compose.yml 内容 ===')
stdin, stdout, stderr = client.exec_command('cat /opt/inv-mqtt/deploy/docker-compose.yml')
print(stdout.read().decode()[:2000])

# 尝试手动执行 docker compose
print('\n=== 尝试手动执行 docker compose ===')
stdin, stdout, stderr = client.exec_command("cd /opt/inv-mqtt/deploy && sudo -S -p '' docker compose config")
stdin.write(sudo_stdin_password() + "\n")
stdin.flush()
print(stdout.read().decode())
print(stderr.read().decode())

client.close()
