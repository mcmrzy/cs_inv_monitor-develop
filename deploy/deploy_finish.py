#!/usr/bin/env python3
"""
光伏逆变器监控系统 - 完成部署脚本
在服务器上拉取代码并启动 Docker 服务
"""

import paramiko
import sys
import time

# 服务器配置
SERVER = "192.168.8.50"
USERNAME = "cskj"
PASSWORD = "REDACTED_ROTATE_CREDENTIAL"
REMOTE_DIR = "/opt/inv-mqtt"
GIT_REPO = "https://gitee.com/your-username/cs_inv_monitor.git"  # 修改为你的 Git 仓库地址

def create_ssh_client():
    """创建 SSH 客户端"""
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(SERVER, username=USERNAME, password=PASSWORD)
    return client

def execute_command(client, command, description="", use_sudo=False):
    """执行远程命令"""
    if description:
        print(f"\n[{description}]")
    
    if use_sudo:
        command = f"echo '{PASSWORD}' | sudo -S {command}"
    
    stdin, stdout, stderr = client.exec_command(command)
    
    output = stdout.read().decode('utf-8')
    error = stderr.read().decode('utf-8')
    
    if output:
        print(output)
    if error:
        if "[sudo]" not in error and "password" not in error.lower():
            print(f"错误: {error}", file=sys.stderr)
    
    return output, error

def main():
    print("=" * 60)
    print("光伏逆变器监控系统 - 完成部署")
    print("=" * 60)
    
    try:
        # 1. 创建 SSH 连接
        print("\n[1/5] 连接到服务器...")
        client = create_ssh_client()
        print("✓ SSH 连接成功")
        
        # 2. 检查服务器环境
        print("\n[2/5] 检查服务器环境...")
        execute_command(client, "docker --version", "检查 Docker")
        execute_command(client, "docker-compose --version", "检查 Docker Compose")
        
        # 3. 克隆代码（如果还没有）
        print("\n[3/5] 准备代码...")
        execute_command(client, f"cd {REMOTE_DIR} && ls -la", "检查目录")
        
        # 4. 停止现有服务
        print("\n[4/5] 停止现有服务...")
        execute_command(client, f"cd {REMOTE_DIR}/deploy && docker-compose down", "停止服务", use_sudo=True)
        
        # 5. 启动服务
        print("\n[5/5] 启动 Docker 服务...")
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
        
        # 关闭连接
        client.close()
        
    except Exception as e:
        print(f"\n错误: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
