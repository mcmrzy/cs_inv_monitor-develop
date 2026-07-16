#!/usr/bin/env python3
"""Diagnose bridge message types and heartbeat flow."""
import paramiko
import time

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('jiuxiaoyw.online', username='ubuntu', password='20040202sA', timeout=30)

def run(cmd):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=30)
    return stdout.read().decode().strip(), stderr.read().decode().strip()

# 1. Check bridge full logs for message type details
print('=== Bridge Full Logs ===')
out, _ = run('docker logs mqtt-kafka-bridge 2>&1 | tail -30')
print(out)

# 2. Check if bridge received any heartbeat messages
print('\n=== Bridge logs grep heartbeat ===')
out, _ = run('docker logs mqtt-kafka-bridge 2>&1 | grep -i heartbeat')
print(out if out else 'No heartbeat messages in bridge logs')

# 3. Check EMQX topics being published by device
print('\n=== EMQX subscriptions for device ===')
out, _ = run('docker exec emqx-5.8.9 emqx ctl topics list 2>/dev/null | grep H1CNA00135000014 | head -20')
print(out if out else 'Cannot list EMQX topics (command not available)')

# 4. Check EMQX webhook configuration
print('\n=== EMQX webhook bridges ===')
out, _ = run('docker exec emqx-5.8.9 emqx ctl bridges list 2>/dev/null || echo "bridges command not available"')
print(out)

# 5. Monitor bridge for 60 seconds to capture new messages
print('\n=== Monitoring bridge for 60s ===')
stats_before, _ = run('wget -qO- --timeout=5 http://localhost:18088/stats 2>/dev/null')
print(f'Before: {stats_before}')
time.sleep(60)
stats_after, _ = run('wget -qO- --timeout=5 http://localhost:18088/stats 2>/dev/null')
print(f'After:  {stats_after}')

# 6. Check new bridge logs
print('\n=== New bridge logs ===')
out, _ = run('docker logs mqtt-kafka-bridge --tail 10 2>&1')
print(out)

# 7. Check if device is publishing heartbeat via MQTT
print('\n=== Check MQTT heartbeat topic ===')
out, _ = run('docker exec emqx-5.8.9 emqx ctl topics list 2>/dev/null | grep heartbeat | head -5')
print(out if out else 'No heartbeat topics found')

# 8. Alternative: check EMQX dashboard API for webhook info
print('\n=== EMQX API: webhooks ===')
out, _ = run('curl -s -u admin:public http://localhost:18083/api/v5/webhooks 2>/dev/null | python3 -m json.tool 2>/dev/null | head -50')
print(out if out else 'EMQX API not accessible or no webhooks')

ssh.close()
print('\nDone!')
