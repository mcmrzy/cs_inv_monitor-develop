#!/usr/bin/env python3
"""
光伏逆变器监控系�?- 服务器部署脚�?
服务�? cskj@example.invalid
"""

import subprocess
import sys
import time
import os

# 配置
SERVER = "cskj@example.invalid"
PASSWORD = "CHANGE_ME_ROTATE_CREDENTIAL"
REMOTE_DIR = "/opt/inv-mqtt"

def run_ssh_command(command, interactive=True):
    """执行 SSH 命令"""
    ssh_cmd = f'ssh -o StrictHostKeyChecking=no {SERVER} "{command}"'
    if interactive:
        # 使用 subprocess 执行，允许交互式输入
        process = subprocess.Popen(
            ssh_cmd,
            shell=True,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        # 输入密码
        time.sleep(2)
        process.stdin.write(PASSWORD + '\n')
        process.stdin.flush()
        return process
    else:
        return subprocess.run(ssh_cmd, shell=True, capture_output=True, text=True)

def run_scp_command(source, destination):
    """执行 SCP 命令"""
    scp_cmd = f'scp -o StrictHostKeyChecking=no -r {source} {SERVER}:{destination}'
    process = subprocess.Popen(
        scp_cmd,
        shell=True,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    # 输入密码
    time.sleep(2)
    process.stdin.write(PASSWORD + '\n')
    process.stdin.flush()
    return process

def main():
    print("=" * 50)
    print("光伏逆变器监控系�?- 服务器部�?)
    print("=" * 50)
    print()

    # 1. 创建远程目录
    print("[1/5] 创建远程目录...")
    process = run_ssh_command(f"mkdir -p {REMOTE_DIR} && ls -la /opt/")
    time.sleep(5)
    process.terminate()

    # 2. 上传代码
    print("\n[2/5] 上传代码到服务器...")
    local_path = "d:/CS_APP_PROJECT/cs_inv_monitor-develop/cs_inv_monitor-develop"
    process = run_scp_command(f"{local_path}/*", f"{REMOTE_DIR}/")
    time.sleep(30)  # 等待上传完成
    process.terminate()

    # 3. 执行部署
    print("\n[3/5] 执行部署...")
    deploy_cmd = f"cd {REMOTE_DIR}/deploy && docker-compose down && docker-compose up -d --build"
    process = run_ssh_command(deploy_cmd)
    time.sleep(60)  # 等待构建完成
    process.terminate()

    # 4. 等待服务启动
    print("\n[4/5] 等待服务启动...")
    time.sleep(30)

    # 5. 检查服务状�?
    print("\n[5/5] 检查服务状�?..")
    process = run_ssh_command("docker ps")
    time.sleep(5)
    process.terminate()

    print("\n" + "=" * 50)
    print("部署完成�?)
    print("访问地址: http://example.invalid:8888")
    print("=" * 50)

if __name__ == "__main__":
    main()
