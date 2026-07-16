#!/usr/bin/env python3
"""Reset offsets and restart device-server."""
import paramiko
import subprocess
import time

# Reset offsets on production server
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('jiuxiaoyw.online', username='ubuntu', password='20040202sA', timeout=30)

def run(cmd):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=60)
    return stdout.read().decode().strip()

K = 'inv-kafka'
BIN = '/opt/kafka/bin'

print('=== 1. Reset parser consumer group ===')
out = run(f'docker exec {K} {BIN}/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group inv-device-server-local-parser --topic inv-telemetry --reset-offsets --to-latest --execute 2>&1')
print(out)

print('\n=== 2. Reset alerts consumer group ===')
out = run(f'docker exec {K} {BIN}/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group inv-device-server-local-alerts --topic inv-alerts --reset-offsets --to-latest --execute 2>&1')
print(out)

print('\n=== 3. Verify parser lag ===')
out = run(f'docker exec {K} {BIN}/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group inv-device-server-local-parser 2>&1')
print(out)

ssh.close()

# Restart device-server locally
print('\n=== 4. Restarting device-server ===')
result = subprocess.run(
    ['docker', 'compose', 'up', '-d', 'inv-device-server'],
    capture_output=True, text=True, timeout=60,
    cwd=r'D:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop\deploy'
)
print(result.stdout)
print(result.stderr)

print('Done!')
