#!/usr/bin/env python3
"""使用其他镜像源部署"""

import paramiko
import time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

# 更新 Docker 镜像源配置
print('更新 Docker 镜像源配置...')
daemon_json = '''{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://dockerhub.azk8s.cn",
    "https://gcr.azk8s.cn",
    "https://quay.azk8s.cn",
    "https://registry.cn-hangzhou.aliyuncs.com"
  ],
  "insecure-registries": [
    "192.168.8.50:4431"
  ]
}'''

# 写入配置
stdin, stdout, stderr = client.exec_command(f"echo 'cskj9527' | sudo -S bash -c 'cat > /etc/docker/daemon.json << EOF\n{daemon_json}\nEOF'")
print(stdout.read().decode())
print(stderr.read().decode())

# 重启 Docker
print('\n重启 Docker 服务...')
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S systemctl restart docker")
print(stdout.read().decode())
print(stderr.read().decode())

# 等待 Docker 启动
time.sleep(10)

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
