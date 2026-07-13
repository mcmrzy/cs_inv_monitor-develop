#!/usr/bin/env python3
"""
光伏逆变器监控系统 - 自动化部署脚本
使用 paramiko 和 scp 库执行远程部署
"""

import paramiko
from scp import SCPClient
import os
import sys
import time

# 服务器配置
SERVER = "192.168.8.50"
USERNAME = "cskj"
PASSWORD = "REDACTED_ROTATE_CREDENTIAL"
REMOTE_DIR = "/opt/inv-mqtt"

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
    
    # 读取输出
    output = stdout.read().decode('utf-8')
    error = stderr.read().decode('utf-8')
    
    if output:
        print(output)
    if error:
        print(f"错误: {error}", file=sys.stderr)
    
    return output, error

def upload_directory(client, local_path, remote_path):
    """上传目录"""
    print(f"\n[上传目录] {local_path} -> {remote_path}")
    
    with SCPClient(client.get_transport()) as scp:
        scp.put(local_path, recursive=True, remote_path=remote_path)

def main():
    print("=" * 60)
    print("光伏逆变器监控系统 - 自动化部署")
    print("=" * 60)
    
    try:
        # 1. 创建 SSH 连接
        print("\n[1/6] 连接到服务器...")
        client = create_ssh_client()
        print("✓ SSH 连接成功")
        
        # 2. 创建远程目录
        print("\n[2/6] 创建远程目录...")
        execute_command(client, f"mkdir -p {REMOTE_DIR}", "创建目录", use_sudo=True)
        execute_command(client, f"chown -R {USERNAME}:{USERNAME} {REMOTE_DIR}", "设置权限", use_sudo=True)
        
        # 3. 上传代码
        print("\n[3/6] 上传代码到服务器...")
        local_path = r"d:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop"
        
        # 上传 deploy 目录
        deploy_path = os.path.join(local_path, "deploy")
        upload_directory(client, deploy_path, f"{REMOTE_DIR}/")
        
        # 上传其他必要目录
        for dir_name in ["inv_api_server", "inv_device_server", "api-gateway", "inv-admin-frontend", "database"]:
            dir_path = os.path.join(local_path, dir_name)
            if os.path.exists(dir_path):
                upload_directory(client, dir_path, f"{REMOTE_DIR}/")
        
        print("✓ 代码上传完成")
        
        # 4. 创建环境配置文件
        print("\n[4/6] 创建环境配置文件...")
        env_content = """DB_HOST=postgres
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=REDACTED_ROTATE_CREDENTIAL
DB_NAME=inv_mqtt
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=RCq/G7b4T00dt5bprW7o34c/OOgPHPKe55Iwz3GvQYQ=
JWT_SECRET=REDACTED_ROTATE_CREDENTIAL
API_SERVER_URL=http://inv-api-server:8080
DEVICE_SERVER_URL=http://inv-device-server:8081
INTERNAL_KEY=inv-monitor-internal-secret-2026
MQTT_BROKER=jiuxiaoyw.online
MQTT_PORT=8883
MQTT_CLIENT_ID=CSKJ-INV-SERVER-DEVICE-LOCAL
MQTT_USERNAME=CSKJ-INV-SERVER-DEVICE
MQTT_PASSWORD=REDACTED_ROTATE_CREDENTIAL
MQTT_TLS_INSECURE=true
EMAIL_HOST=smtp.qq.com
EMAIL_PORT=465
EMAIL_USER=sunhaoyu0221@qq.com
EMAIL_PASS=REDACTED_ROTATE_CREDENTIAL
EMAIL_FROM=sunhaoyu0221@qq.com"""
        
        # 写入 .env 文件
        execute_command(client, f"cat > {REMOTE_DIR}/deploy/.env << 'EOF'\n{env_content}\nEOF", "创建 .env 文件", use_sudo=True)
        
        # 5. 停止现有服务
        print("\n[5/6] 停止现有服务...")
        execute_command(client, f"cd {REMOTE_DIR}/deploy && docker-compose down", "停止服务", use_sudo=True)
        
        # 6. 启动服务
        print("\n[6/6] 启动服务...")
        execute_command(client, f"cd {REMOTE_DIR}/deploy && docker-compose up -d --build", "启动服务", use_sudo=True)
        
        # 等待服务启动
        print("\n等待服务启动...")
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
