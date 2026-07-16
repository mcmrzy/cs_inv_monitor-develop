#!/usr/bin/env python3
"""Diagnose heartbeat message flow - check bridge message details and EMQX topics."""
import paramiko
import time

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('jiuxiaoyw.online', username='ubuntu', password='20040202sA', timeout=30)

def run(cmd):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=30)
    return stdout.read().decode().strip(), stderr.read().decode().strip()

# 1. Bridge full logs - check what topics/msg_types are being received
print('=== 1. Bridge full logs (all) ===')
out, _ = run('docker logs mqtt-kafka-bridge 2>&1')
print(out[-3000:] if len(out) > 3000 else out)

# 2. Bridge logs grep for msg_type or topic
print('\n=== 2. Bridge logs: msg_type distribution ===')
out, _ = run('docker logs mqtt-kafka-bridge 2>&1 | grep -oP "msg_type[^\"]*\"[^\"]*\"" | sort | uniq -c | sort -rn')
print(out if out else 'No msg_type patterns found')

# 3. Bridge logs grep for topic
print('\n=== 3. Bridge logs: topic distribution ===')
out, _ = run('docker logs mqtt-kafka-bridge 2>&1 | grep -oP "topic[^\"]*\"[^\"]*\"" | sort | uniq -c | sort -rn')
print(out if out else 'No topic patterns found')

# 4. Check EMQX for device topics
print('\n=== 4. EMQX: device active topics ===')
out, _ = run('curl -s -u admin:public http://localhost:18083/api/v5/clients 2>/dev/null | python3 -c "import sys,json; data=json.load(sys.stdin); [print(c.get(\'clientid\',\'?\'), c.get(\'proto_ver\',\'?\')) for c in data]" 2>/dev/null')
print(out if out else 'Cannot list EMQX clients')

# 5. Check EMQX topics list for heartbeat
print('\n=== 5. EMQX: heartbeat topics ===')
out, _ = run('curl -s -u admin:public "http://localhost:18083/api/v5/topics?topic=cs_inv/%2B/heartbeat&limit=10" 2>/dev/null | python3 -m json.tool 2>/dev/null')
print(out if out else 'Cannot query EMQX topics')

# 6. Check EMQX subscriptions for heartbeat
print('\n=== 6. EMQX: all cs_inv topics ===')
out, _ = run('curl -s -u admin:public "http://localhost:18083/api/v5/topics?topic=cs_inv/%23&limit=50" 2>/dev/null | python3 -c "import sys,json; data=json.load(sys.stdin); [print(t.get(\'topic\',\'?\')) for t in (data if isinstance(data, list) else data.get(\'data\',[]))]" 2>/dev/null')
print(out if out else 'Cannot list topics')

# 7. Direct EMQX topics command
print('\n=== 7. EMQX topics command ===')
out, _ = run('docker exec emqx-5.8.9 emqx ctl topics list 2>/dev/null | head -30')
print(out if out else 'emqx ctl topics not available')

# 8. Check bridge stats now
print('\n=== 8. Bridge stats (current) ===')
out, _ = run('wget -qO- --timeout=5 http://localhost:18088/stats 2>/dev/null')
print(out)

# 9. Wait 60s and check again to see if heartbeat arrives
print('\n=== 9. Waiting 60s to monitor new messages... ===')
time.sleep(60)
out, _ = run('wget -qO- --timeout=5 http://localhost:18088/stats 2>/dev/null')
print(f'After 60s: {out}')

# 10. Check device-server logs for any heartbeat activity
print('\n=== 10. Device-server heartbeat check (local Docker) ===')
# This runs on local machine, not server
ssh.close()

import subprocess
result = subprocess.run(
    ['docker', 'exec', 'inv-device-server', 'sh', '-c',
     'grep -c "heartbeat" /app/logs/device-server.log 2>/dev/null; echo "---"; grep "handleHeartbeat\\|ParseHeartbeat\\|heartbeat" /app/logs/device-server.log 2>/dev/null | tail -5'],
    capture_output=True, text=True, timeout=30
)
print(result.stdout if result.stdout else 'No heartbeat references in device-server logs')
print(result.stderr if result.stderr else '')

# 11. Check what messages device-server received recently
result2 = subprocess.run(
    ['docker', 'exec', 'inv-device-server', 'sh', '-c',
     'tail -20 /app/logs/device-server.log'],
    capture_output=True, text=True, timeout=30
)
print('\n=== 11. Device-server recent logs ===')
print(result2.stdout[-2000:] if result2.stdout else 'No logs')

print('\nDone!')
