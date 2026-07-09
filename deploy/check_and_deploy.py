#!/usr/bin/env python3
"""
光伏逆变器监控系统 - 检查并完成部署
"""

import paramiko
import sys
import time

# 服务器配置
SERVER = "192.168.8.50"
USERNAME = "cskj"
PASSWORD = "cskj9527"
REMOTE_DIR = "/opt/inv-mqtt"

def create_ssh_client():
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(SERVER, username=USERNAME, password=PASSWORD)
    return client

def execute_command(client, command, description="", use_sudo=False):
    if description:
        print(f"\n[{description}]")
    
    if use_sudo:
        command = f"echo '{PASSWORD}' | sudo -S {command}"
    
    stdin, stdout, stderr = client.exec_command(command)
    output = stdout.read().decode('utf-8')
    error = stderr.read().decode('utf-8')
    
    if output:
        print(output)
    if error and "[sudo]" not in error:
        print(f"错误: {error}", file=sys.stderr)
    
    return output, error

def main():
    print("=" * 60)
    print("光伏逆变器监控系统 - 检查并完成部署")
    print("=" * 60)
    
    try:
        client = create_ssh_client()
        print("✓ SSH 连接成功")
        
        # 1. 检查目录结构
        print("\n[1/4] 检查服务器目录结构...")
        execute_command(client, f"ls -la {REMOTE_DIR}/", "检查目录")
        
        # 2. 检查 deploy 目录
        print("\n[2/4] 检查 deploy 目录...")
        execute_command(client, f"ls -la {REMOTE_DIR}/deploy/", "检查 deploy 目录")
        
        # 3. 检查 Docker
        print("\n[3/4] 检查 Docker 环境...")
        execute_command(client, "docker --version", "Docker 版本")
        execute_command(client, "docker-compose --version", "Docker Compose 版本")
        
        # 4. 启动服务
        print("\n[4/4] 启动 Docker 服务...")
        execute_command(client, f"cd {REMOTE_DIR}/deploy && docker-compose up -d --build", "启动服务", use_sudo=True)
        
        # 等待服务启动
        print("\n等待服务启动（约 30 秒）...")
        time.sleep(30)
        
        # 检查服务状态
        print("\n" + "=" * 60)
        print("服务状态:")
        print("=" * 60)
        execute_command(client, "docker ps", "检查服务状态")
        
        print("\n" + "=" * 60)
        print("部署完成！")
        print("=" * 60)
        print(f"API 网关: http://{SERVER}:8888")
        print(f"管理后台: http://{SERVER}:3000")
        print("=" * 60)
        
        client.close()
        
    except Exception as e:
        print(f"\n错误: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
