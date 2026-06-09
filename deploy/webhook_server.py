#!/usr/bin/env python3
"""
Git Webhook 处理服务
监听 GitLab/GitHub Webhook 自动触发部署

安装:
    pip install flask hmac hashlib

使用:
    python webhook_server.py --port 5000 --secret your-webhook-secret
"""

import argparse
import hashlib
import hmac
import json
import logging
import os
import subprocess
import threading
import time
from datetime import datetime
from flask import Flask, request, jsonify

app = Flask(__name__)

# 配置
CONFIG = {
    'app_dir': '/opt/inv-mqtt',
    'branch': 'main',
    'deploy_script': '/opt/inv-mqtt/deploy/deploy.sh',
    'log_file': '/var/log/inv-mqtt/webhook.log',
    'allowed_ips': [],  # 允许的 IP 列表，留空则允许所有
    'secret': '',
}

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(CONFIG['log_file']),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

deploy_lock = threading.Lock()
last_deploy_time = 0
DEPLOY_COOLDOWN = 60  # 部署冷却时间（秒）


def verify_signature(payload, signature, secret):
    """验证 Webhook 签名"""
    if not secret:
        return True  # 未配置密钥时跳过验证

    mac = hmac.new(
        secret.encode('utf-8'),
        payload,
        hashlib.sha256
    )
    expected = 'sha256=' + mac.hexdigest()

    return hmac.compare_digest(expected, signature)


def get_client_ip():
    """获取客户端 IP"""
    if request.headers.get('X-Forwarded-For'):
        return request.headers.get('X-Forwarded-For').split(',')[0].strip()
    return request.headers.get('X-Real-IP', request.remote_addr)


def run_deploy(branch=None):
    """执行部署"""
    global last_deploy_time

    if deploy_lock.locked():
        return False, "部署正在进行中..."

    with deploy_lock:
        last_deploy_time = time.time()
        branch = branch or CONFIG['branch']

        try:
            logger.info(f"开始部署分支: {branch}")

            # 更新代码
            os.chdir(CONFIG['app_dir'])
            subprocess.run(['git', 'fetch', 'origin'], check=True, capture_output=True)
            subprocess.run(['git', 'checkout', branch], check=True, capture_output=True)
            subprocess.run(['git', 'pull', 'origin', branch], check=True, capture_output=True)

            # 执行部署脚本
            result = subprocess.run(
                [CONFIG['deploy_script']],
                capture_output=True,
                text=True,
                timeout=600
            )

            if result.returncode == 0:
                logger.info("部署成功")
                return True, "部署成功"
            else:
                logger.error(f"部署失败: {result.stderr}")
                return False, f"部署失败: {result.stderr}"

        except subprocess.TimeoutExpired:
            logger.error("部署超时")
            return False, "部署超时"
        except Exception as e:
            logger.error(f"部署异常: {e}")
            return False, str(e)


def deploy_in_background(branch):
    """后台执行部署"""
    thread = threading.Thread(target=run_deploy, args=(branch,))
    thread.daemon = True
    thread.start()


@app.route('/webhook', methods=['POST'])
def handle_webhook():
    """处理 Webhook 请求"""
    client_ip = get_client_ip()
    logger.info(f"收到 Webhook 请求 from {client_ip}")

    # IP 白名单检查
    if CONFIG['allowed_ips'] and client_ip not in CONFIG['allowed_ips']:
        logger.warning(f"拒绝非白名单 IP: {client_ip}")
        return jsonify({'error': 'IP not allowed'}), 403

    # 获取签名
    signature = request.headers.get('X-Hub-Signature-256') or \
               request.headers.get('X-Gitlab-Token')

    # 验证签名
    payload = request.get_data()
    if not verify_signature(payload, signature, CONFIG['secret']):
        logger.warning("签名验证失败")
        return jsonify({'error': 'Invalid signature'}), 401

    # 解析事件
    event = request.headers.get('X-GitHub-Event') or \
            request.headers.get('X-Gitlab-Event', 'push')

    logger.info(f"事件类型: {event}")

    if event in ['push', 'Push Hook']:
        data = request.get_json() or {}

        # 检查是否为我们的分支
        branch = data.get('ref', '').replace('refs/heads/', '')
        if branch != CONFIG['branch']:
            logger.info(f"忽略分支: {branch}")
            return jsonify({'message': f'Ignored branch: {branch}'})

        # 检查部署冷却
        if time.time() - last_deploy_time < DEPLOY_COOLDOWN:
            logger.info("部署冷却中...")
            return jsonify({'message': 'Deploy in cooldown'})

        # 后台执行部署
        deploy_in_background(branch)

        return jsonify({
            'message': 'Deployment started',
            'branch': branch
        })

    elif event in ['merge_request', 'Merge Request Hook']:
        data = request.get_json() or {}
        action = data.get('object_attributes', {}).get('action')

        if action == 'merge':
            logger.info("检测到合并请求，触发部署")
            deploy_in_background(CONFIG['branch'])
            return jsonify({'message': 'Deployment started on merge'})

    return jsonify({'message': 'Event ignored'})


@app.route('/health', methods=['GET'])
def health():
    """健康检查"""
    return jsonify({
        'status': 'ok',
        'deploying': deploy_lock.locked(),
        'last_deploy': datetime.fromtimestamp(last_deploy_time).isoformat() if last_deploy_time else None
    })


@app.route('/status', methods=['GET'])
def status():
    """部署状态"""
    return jsonify({
        'deploying': deploy_lock.locked(),
        'last_deploy_time': last_deploy_time,
        'last_deploy': datetime.fromtimestamp(last_deploy_time).isoformat() if last_deploy_time else None
    })


@app.route('/deploy', methods=['POST'])
def manual_deploy():
    """手动触发部署（需要认证）"""
    secret = request.headers.get('X-Deploy-Secret')
    if secret != CONFIG.get('deploy_secret'):
        return jsonify({'error': 'Unauthorized'}), 401

    branch = request.json.get('branch', CONFIG['branch'])
    deploy_in_background(branch)

    return jsonify({'message': 'Deployment started', 'branch': branch})


def main():
    parser = argparse.ArgumentParser(description='Git Webhook 自动部署服务')
    parser.add_argument('--port', type=int, default=5000, help='监听端口')
    parser.add_argument('--host', default='0.0.0.0', help='监听地址')
    parser.add_argument('--secret', default='', help='Webhook 密钥')
    parser.add_argument('--app-dir', default='/opt/inv-mqtt', help='应用目录')
    parser.add_argument('--branch', default='main', help='部署分支')
    args = parser.parse_args()

    CONFIG['secret'] = args.secret
    CONFIG['app_dir'] = args.app_dir
    CONFIG['branch'] = args.branch

    logger.info(f"启动 Webhook 服务 on {args.host}:{args.port}")

    app.run(host=args.host, port=args.port, debug=False)


if __name__ == '__main__':
    main()
