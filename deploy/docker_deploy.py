#!/usr/bin/env python3
"""
光伏逆变器监控系统 - Docker 一键部署
"""

import paramiko
import sys
import time

# 服务器配置
SERVER = "192.168.8.50"
USERNAME = "cskj"
PASSWORD = "cskj9527"
REMOTE_DIR = "/opt/inv-mqtt"

def ssh_connect():
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(SERVER, username=USERNAME, password=PASSWORD)
    return client

def run_cmd(client, cmd, use_sudo=True):
    if use_sudo:
        cmd = f"echo '{PASSWORD}' | sudo -S {cmd}"
    stdin, stdout, stderr = client.exec_command(cmd)
    out = stdout.read().decode('utf-8')
    err = stderr.read().decode('utf-8')
    return out, err

def main():
    print("=" * 50)
    print("光伏逆变器监控系统 - Docker 部署")
    print("=" * 50)
    
    try:
        # 连接服务器
        print("\n[1/6] 连接服务器...")
        client = ssh_connect()
        print("✓ 连接成功")
        
        # 检查 Docker
        print("\n[2/6] 检查 Docker 环境...")
        out, _ = run_cmd(client, "docker --version", use_sudo=False)
        print(f"Docker: {out.strip()}")
        out, _ = run_cmd(client, "docker-compose --version", use_sudo=False)
        print(f"Docker Compose: {out.strip()}")
        
        # 检查项目目录
        print("\n[3/6] 检查项目目录...")
        out, _ = run_cmd(client, f"ls -la {REMOTE_DIR}/deploy/", use_sudo=False)
        print(out)
        
        # 停止现有服务
        print("\n[4/6] 停止现有服务...")
        out, err = run_cmd(client, f"cd {REMOTE_DIR}/deploy && docker-compose down")
        if out: print(out)
        
        # 启动服务
        print("\n[5/6] 启动 Docker 服务...")
        out, err = run_cmd(client, f"cd {REMOTE_DIR}/deploy && docker-compose up -d --build")
        if out: print(out)
        if err and "sudo" not in err: print(f"错误: {err}")
        
        # 等待启动
        print("\n等待服务启动...")
        time.sleep(30)
        
        # 检查状态
        print("\n[6/6] 检查服务状态...")
        out, _ = run_cmd(client, "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'", use_sudo=False)
        print(out)
        
        print("\n" + "=" * 50)
        print("部署完成！")
        print("=" * 50)
        print(f"API 网关: http://{SERVER}:8888")
        print(f"管理后台: http://{SERVER}:3000")
        print("=" * 50)
        
        client.close()
        
    except Exception as e:
        print(f"\n错误: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
