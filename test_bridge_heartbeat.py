#!/usr/bin/env python3
"""Diagnose why bridge doesn't receive heartbeat messages."""
import paramiko
import time

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('jiuxiaoyw.online', username='ubuntu', password='20040202sA', timeout=30)

def run(cmd):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=30)
    return stdout.read().decode().strip(), stderr.read().decode().strip()

# 1. Test bridge webhook with a simulated heartbeat message
print('=== 1. Test bridge webhook with heartbeat ===')
test_payload = '{"topic":"cs_inv/H1CNA00135000014/heartbeat","payload":"{\\"t\\":1784182560,\\"v\\":1,\\"data\\":{\\"ac\\":[220.1,8.51]}}","qos":0}'
out, err = run(f"curl -s -X POST -H 'Content-Type: application/json' -d '{test_payload}' http://localhost:18088/webhook 2>&1")
print(f'Response: {out}')
print(f'Error: {err}') if err else None

# 2. Check bridge stats before/after
print('\n=== 2. Bridge stats ===')
out, _ = run('wget -qO- --timeout=5 http://localhost:18088/stats 2>/dev/null')
print(f'Stats: {out}')

# 3. Check bridge logs for the test message
print('\n=== 3. Bridge recent logs ===')
out, _ = run('docker logs mqtt-kafka-bridge --tail 15 2>&1')
print(out)

# 4. Check EMQX webhook rule details
print('\n=== 4. EMQX webhook config ===')
# Try to access EMQX Dashboard API for webhooks (v5 uses different auth)
out, _ = run('curl -s -u admin:public http://localhost:18083/api/v5/connectors 2>/dev/null | python3 -m json.tool 2>/dev/null | head -30')
print(out if out else 'Cannot access EMQX connectors API')

# 5. Check EMQX actions/rules
print('\n=== 5. EMQX actions ===')
out, _ = run('curl -s -u admin:public http://localhost:18083/api/v5/actions 2>/dev/null | python3 -m json.tool 2>/dev/null | head -50')
print(out if out else 'Cannot access EMQX actions API')

# 6. Check EMQX rules  
print('\n=== 6. EMQX rules ===')
out, _ = run('curl -s -u admin:public http://localhost:18083/api/v5/rules 2>/dev/null | python3 -m json.tool 2>/dev/null | head -80')
print(out if out else 'Cannot access EMQX rules API')

# 7. Check if heartbeat topic is retained or not
print('\n=== 7. EMQX retained messages check ===')
out, _ = run('docker exec emqx-5.8.9 emqx ctl retainer info 2>/dev/null')
print(out if out else 'retainer info not available')

# 8. Publish a test message to heartbeat topic and see if bridge gets it
print('\n=== 8. Publish test heartbeat via EMQX ===')
# Use mosquitto_pub if available, or curl to EMQX publish API
out, _ = run('curl -s -u admin:public -X POST http://localhost:18083/api/v5/publish -H "Content-Type: application/json" -d \'{"topic":"cs_inv/H1CNA00135000014/heartbeat","payload":"{\\\\\\"t\\\\\\":1234,\\\\\\"v\\\\\\":1,\\\\\\"data\\\\\\":{\\\\\\"ac\\\\\\":[220]}}","qos":0,"retain":false,"clientid":"test-pub"}\' 2>&1')
print(f'Publish result: {out}')

# Wait a moment
time.sleep(3)

# Check bridge stats after publish
print('\n=== 9. Bridge stats after publish ===')
out, _ = run('wget -qO- --timeout=5 http://localhost:18088/stats 2>/dev/null')
print(f'Stats: {out}')

# 10. Check bridge logs for received message
print('\n=== 10. Bridge logs after publish ===')
out, _ = run('docker logs mqtt-kafka-bridge --tail 5 2>&1')
print(out)

ssh.close()
print('\nDone!')
