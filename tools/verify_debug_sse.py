#!/usr/bin/env python3
"""端到端验证调试采样 SSE：注册/登录 → 造会话与采样 → 订阅流 → 实时插入新采样点。

本地专用脚本：只允许访问 127.0.0.1 上的本地 API/Redis，密码运行时随机生成，
不落任何真实凭据；数据库写入通过 docker exec 打到本地测试库。
"""
import json
import secrets
import subprocess
import time
from urllib.parse import urlparse

import requests

ALLOWED_HOST = '127.0.0.1'
API = f'http://{ALLOWED_HOST}:8080/api/v1'
SN = 'H1CNA0013700002D'
EMAIL = 'sse-verify@example.com'
PHONE = '13700001234'
CODE = '123456'
# 一次性测试账号，密码每次随机生成（用完即弃，不存在于任何配置里）。
# 注意接口约束 min=6,max=20，随机长度必须落在这个区间内。
PASSWORD = f'Sse{secrets.token_hex(6)}!'


def assert_local(url: str) -> None:
    """只允许 http + 环回地址，避免脚本被改成打内网/元数据服务。"""
    parsed = urlparse(url)
    if parsed.scheme != 'http' or parsed.hostname != ALLOWED_HOST:
        raise RuntimeError(f'only http://{ALLOWED_HOST} is allowed, got {url}')


def post(path: str, payload: dict):
    url = f'{API}{path}'
    assert_local(url)
    return requests.post(url, json=payload, timeout=15)


def docker_exec(*args: str) -> str:
    out = subprocess.run(['docker', 'exec', '-i', *args], capture_output=True, text=True, timeout=60)
    if out.returncode != 0:
        raise RuntimeError(f'docker exec failed: {out.stderr.strip()}')
    return out.stdout.strip()


def psql(sql: str) -> str:
    return docker_exec('inv-postgres', 'psql', '-U', 'postgres', '-d', 'inv_mqtt', '-t', '-A', '-c', sql)


# ── 1. 注册（先写 Redis 验证码）+ 登录 ──
docker_exec('inv-redis', 'redis-cli', 'SET', f'email:{EMAIL}:register', CODE, 'EX', '300')

reg = post('/auth/email-register', {
    'email': EMAIL, 'phone': PHONE, 'password': PASSWORD, 'code': CODE, 'nickname': 'sse-verify',
})
print('register:', reg.status_code, reg.json().get('code'), reg.json().get('message'))
user_id = psql(f"select id from users where phone='{PHONE}'")
print('user_id:', user_id)
psql(f'UPDATE users SET is_system_admin = true WHERE id = {user_id}')

login = post('/auth/login', {'account': PHONE, 'password': PASSWORD})
body = login.json()
token = (body.get('data') or {}).get('token')
print('login:', login.status_code, 'token:', 'yes' if token else 'NO')
if not token:
    raise SystemExit(f'login failed: {body}')

# ── 2. 造一个 active 调试会话 + 一条历史采样 ──
psql(f"DELETE FROM device_debug_sessions WHERE device_sn='{SN}'")
psql(
    "INSERT INTO device_debug_sessions (device_sn, request_id, status, interval_seconds, duration_seconds,"
    f" started_at, expires_at, requested_by, source) VALUES ('{SN}', 'sse-verify-1', 'active', 5, 3600,"
    f" NOW() - INTERVAL '2 minutes', NOW() + INTERVAL '1 hour', {user_id}, 'web')")
print('session_id:', psql(f"select id from device_debug_sessions where device_sn='{SN}' order by id desc limit 1"))


def insert_sample(tag: str, offset_sec: int) -> None:
    psql(
        "INSERT INTO device_telemetry_3min (device_sn, protocol_version, sequence_no, event_time, data_hash, topic,"
        " pv1_voltage, buck1_current, battery_voltage, battery_current, dc_bus_voltage, inv_current,"
        " ac_voltage, ac_current) VALUES"
        f" ('{SN}', 2, 0, NOW() - INTERVAL '{offset_sec} seconds', 'sse-{tag}', 'heartbeat',"
        " 380.5, 5.5, 51.2, 6.3, 410.0, 4.1, 220.8, 13.0)")


insert_sample('seed', 90)

# ── 3. 订阅 SSE，中途插入新采样点，验证是服务端「推」而不是前端「拉」 ──
url = f'{API}/devices/by-sn/{SN}/debug-stream?token={token}&window_minutes=15'
assert_local(url)
print('\n--- SSE ---')
events = []
start = time.time()
with requests.get(url, stream=True, timeout=40) as resp:
    print('status:', resp.status_code, 'content-type:', resp.headers.get('Content-Type'))
    buffer = ''
    injected = False
    for chunk in resp.iter_content(chunk_size=1, decode_unicode=True):
        if chunk:
            buffer += chunk
        if buffer.endswith('\n\n'):
            block = buffer.strip()
            buffer = ''
            if block.startswith(':'):
                print(f'[{time.time() - start:5.1f}s] heartbeat')
                continue
            name, data = '', ''
            for line in block.splitlines():
                if line.startswith('event: '):
                    name = line[7:]
                elif line.startswith('data: '):
                    data = line[6:]
            payload = json.loads(data) if data else {}
            events.append(name)
            summary = {k: (len(v) if isinstance(v, list) else v) for k, v in payload.items()}
            print(f'[{time.time() - start:5.1f}s] event={name} {summary}')
        if not injected and time.time() - start > 3:
            injected = True
            insert_sample('live', 0)
            print(f'[{time.time() - start:5.1f}s] >>> 已插入一条新采样，等待推送')
        if time.time() - start > 12:
            break

print('\nevents seen:', events)
print('RESULT:', 'OK' if 'snapshot' in events and 'samples' in events else 'FAIL')
print('local user id (可留作本地测试账号):', user_id, 'email:', EMAIL)
