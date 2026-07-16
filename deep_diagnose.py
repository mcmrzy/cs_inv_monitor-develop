#!/usr/bin/env python3
"""Deep diagnosis: check heartbeat timing, EMQX forwarding, and bridge message details."""
import paramiko
import time
import json

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('jiuxiaoyw.online', username='ubuntu', password='20040202sA', timeout=30)

def run(cmd):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=60)
    return stdout.read().decode().strip(), stderr.read().decode().strip()

# 1. Check current time on server vs bridge stats
print('=== 1. Server time and bridge stats ===')
out, _ = run('date -u; echo "---"; wget -qO- --timeout=5 http://localhost:18088/stats 2>/dev/null')
print(out)

# 2. Test bridge webhook directly with EMQX v5 message format
print('\n=== 2. Test bridge with EMQX v5 webhook format ===')
# EMQX v5 sends: {"action":"message_publish","clientid":"xxx","username":"xxx","topic":"cs_inv/xxx/heartbeat","payload":"<base64 or raw json>","qos":0,"timestamp":xxx}
# But bridge expects: {"clientid":"xxx","topic":"xxx","payload":"xxx","qos":0,"ts":xxx}
# The bridge struct only picks up known fields, so extra fields are ignored
test_msg = json.dumps({
    "clientid": "H1CNA00135000014",
    "username": "",
    "topic": "cs_inv/H1CNA00135000014/heartbeat",
    "payload": json.dumps({"t": 1784182560, "v": 1, "data": {"ac": [220.1, 8.51, 1854.8, 1873.6, 50, 0.99, 29.9, 2.5], "bat": [75]*23, "pv": [120.1]*7, "sys": [1]*11, "eng": [15.6]*12, "cells": [[3.3]*16, [3.7]*16]}}),
    "qos": 0,
    "ts": 1784182560000
})
out, err = run(f"curl -s -w '\\nHTTP_CODE:%{{http_code}}' -X POST -H 'Content-Type: application/json' -d '{test_msg}' http://localhost:18088/webhook 2>&1")
print(f'Response: {out}')

# 3. Check bridge stats after test
print('\n=== 3. Bridge stats after test ===')
time.sleep(2)
out, _ = run('wget -qO- --timeout=5 http://localhost:18088/stats 2>/dev/null')
print(f'Stats: {out}')

# 4. Check Kafka for heartbeat message (via device-server logs)
print('\n=== 4. Device-server logs after test (heartbeat?) ===')
# Check local device-server for heartbeat processing
import subprocess
result = subprocess.run(
    ['docker', 'exec', 'inv-device-server', 'sh', '-c',
     'grep "heartbeat" /app/logs/device-server.log | tail -5'],
    capture_output=True, text=True, timeout=30
)
print(result.stdout if result.stdout else 'No heartbeat in device-server logs')

# 5. Monitor bridge for 200 seconds to catch heartbeat (180s interval)
print('\n=== 5. Monitoring bridge for 200s (waiting for heartbeat)... ===')
stats_start, _ = run('wget -qO- --timeout=5 http://localhost:18088/stats 2>/dev/null')
print(f'Start: {stats_start}')

time.sleep(200)

stats_end, _ = run('wget -qO- --timeout=5 http://localhost:18088/stats 2>/dev/null')
print(f'End:   {stats_end}')

# 6. Check bridge logs for message details
print('\n=== 6. Bridge logs (recent) ===')
out, _ = run('docker logs mqtt-kafka-bridge --tail 15 2>&1')
print(out)

# 7. Check device-server for any new heartbeat messages
print('\n=== 7. Device-server heartbeat check ===')
result2 = subprocess.run(
    ['docker', 'exec', 'inv-device-server', 'sh', '-c',
     'grep -c "heartbeat" /app/logs/device-server.log 2>/dev/null; echo "---"; grep "heartbeat" /app/logs/device-server.log | tail -3'],
    capture_output=True, text=True, timeout=30
)
print(result2.stdout if result2.stdout else 'No heartbeat references')

# 8. Check device_telemetry_3min
print('\n=== 8. device_telemetry_3min check ===')
result3 = subprocess.run(
    ['docker', 'exec', 'inv-postgres', 'psql', '-U', 'postgres', '-d', 'inv_mqtt', '-c',
     "SELECT COUNT(*) FROM device_telemetry_3min WHERE device_sn = 'H1CNA00135000014'"],
    capture_output=True, text=True, timeout=30
)
print(result3.stdout if result3.stdout else result3.stderr)

ssh.close()
print('\nDone!')
