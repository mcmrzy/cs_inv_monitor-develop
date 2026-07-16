#!/usr/bin/env python3
"""Reset Kafka consumer group offsets to latest for local device-server."""
import paramiko

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('jiuxiaoyw.online', username='ubuntu', password='20040202sA', timeout=30)

def run(cmd):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=60)
    return stdout.read().decode().strip(), stderr.read().decode().strip()

K = 'inv-kafka'
BIN = '/opt/kafka/bin'

# Reset parser consumer group to latest
print('=== 1. Reset inv-device-server-local-parser to LATEST ===')
out, _ = run(f'docker exec {K} {BIN}/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group inv-device-server-local-parser --topic inv-telemetry --reset-offsets --to-latest --execute 2>&1')
print(out)

# Reset alerts consumer group to latest
print('\n=== 2. Reset inv-device-server-local-alerts to LATEST ===')
out, _ = run(f'docker exec {K} {BIN}/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group inv-device-server-local-alerts --topic inv-alerts --reset-offsets --to-latest --execute 2>&1')
print(out)

# Verify the lag after reset
print('\n=== 3. Verify lag after reset ===')
out, _ = run(f'docker exec {K} {BIN}/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group inv-device-server-local-parser 2>&1')
print(out)

# Bridge stats
print('\n=== 4. Bridge stats ===')
out, _ = run('wget -qO- --timeout=5 http://localhost:18088/stats 2>/dev/null')
print(out)

ssh.close()
print('\nDone! Now the local device-server should start receiving new messages including heartbeat.')
