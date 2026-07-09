#!/usr/bin/env python3
"""
光伏逆变器监控系统 - 轻量级部署脚本
只上传 deploy 目录，其他代码从 Git 克隆
"""

import paramiko
import os
import sys
import time

# 服务器配置
SERVER = "192.168.8.50"
USERNAME = "cskj"
PASSWORD = "cskj9527"
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
    
    output = stdout.read().decode('utf-8')
    error = stderr.read().decode('utf-8')
    
    if output:
        print(output)
    if error:
        # 忽略 sudo 密码提示
        if "[sudo]" not in error:
            print(f"错误: {error}", file=sys.stderr)
    
    return output, error

def main():
    print("=" * 60)
    print("光伏逆变器监控系统 - 轻量级部署")
    print("=" * 60)
    
    try:
        # 1. 创建 SSH 连接
        print("\n[1/4] 连接到服务器...")
        client = create_ssh_client()
        print("✓ SSH 连接成功")
        
        # 2. 创建远程目录
        print("\n[2/4] 创建远程目录...")
        execute_command(client, f"mkdir -p {REMOTE_DIR}", "创建目录", use_sudo=True)
        execute_command(client, f"chown -R {USERNAME}:{USERNAME} {REMOTE_DIR}", "设置权限", use_sudo=True)
        
        # 3. 上传 deploy 目录（使用 SFTP 而不是 SCP）
        print("\n[3/4] 上传部署文件...")
        
        # 创建 SFTP 客户端
        sftp = client.open_sftp()
        
        # 上传 deploy 目录
        local_deploy_path = r"d:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop\deploy"
        remote_deploy_path = f"{REMOTE_DIR}/deploy"
        
        # 确保远程目录存在
        execute_command(client, f"mkdir -p {remote_deploy_path}", use_sudo=True)
        execute_command(client, f"chown -R {USERNAME}:{USERNAME} {remote_deploy_path}", use_sudo=True)
        
        # 上传文件
        for root, dirs, files in os.walk(local_deploy_path):
            # 计算远程路径
            rel_path = os.path.relpath(root, local_deploy_path)
            remote_path = os.path.join(remote_deploy_path, rel_path).replace("\\", "/")
            
            # 创建远程目录
            try:
                sftp.mkdir(remote_path)
            except:
                pass
            
            # 上传文件
            for file in files:
                local_file = os.path.join(root, file)
                remote_file = os.path.join(remote_path, file)
                
                print(f"  上传: {file}")
                sftp.put(local_file, remote_file)
        
        sftp.close()
        print("✓ 部署文件上传完成")
        
        # 4. 创建环境配置文件
        print("\n[4/4] 创建环境配置文件...")
        env_content = """DB_HOST=postgres
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=InvMonitor@2026!Secure
DB_NAME=inv_mqtt
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=RCq/G7b4T00dt5bprW7o34c/OOgPHPKe55Iwz3GvQYQ=
JWT_SECRET=fq2T9il2RpZpSmUH1pLbV4cIwaEWypg3wjT629+GPeassiiW6A+wXdC+4jennVyN
API_SERVER_URL=http://inv-api-server:8080
DEVICE_SERVER_URL=http://inv-device-server:8081
INTERNAL_KEY=inv-monitor-internal-secret-2026
MQTT_BROKER=jiuxiaoyw.online
MQTT_PORT=8883
MQTT_CLIENT_ID=CSKJ-INV-SERVER-DEVICE-LOCAL
MQTT_USERNAME=CSKJ-INV-SERVER-DEVICE
MQTT_PASSWORD=CSKJINVSERVERDEVICE
MQTT_TLS_INSECURE=true
EMAIL_HOST=smtp.qq.com
EMAIL_PORT=465
EMAIL_USER=sunhaoyu0221@qq.com
EMAIL_PASS=uqcomryxtnimbeha
EMAIL_FROM=sunhaoyu0221@qq.com"""
        
        # 写入 .env 文件
        execute_command(client, f"cat > {REMOTE_DIR}/deploy/.env << 'EOF'\n{env_content}\nEOF", "创建 .env 文件", use_sudo=True)
        execute_command(client, f"chown -R {USERNAME}:{USERNAME} {REMOTE_DIR}/deploy/.env", use_sudo=True)
        
        # 关闭连接
        client.close()
        
        print("\n" + "=" * 60)
        print("部署文件上传完成！")
        print("=" * 60)
        print("\n请在服务器上执行以下命令完成部署：")
        print(f"\nssh {USERNAME}@{SERVER}")
        print(f"cd {REMOTE_DIR}/deploy")
        print("docker-compose up -d --build")
        print("\n访问地址:")
        print(f"  API 网关: http://{SERVER}:8888")
        print(f"  管理后台: http://{SERVER}:3000")
        print("=" * 60)
        
    except Exception as e:
        print(f"\n错误: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
