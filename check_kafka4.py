#!/usr/bin/env python3
"""Check Kafka consumer groups and topic messages."""
import paramiko

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('jiuxiaoyw.online', username='ubuntu', password='20040202sA', timeout=30)

def run(cmd):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=60)
    return stdout.read().decode().strip(), stderr.read().decode().strip()

K = 'inv-kafka'
BIN = '/opt/kafka/bin'

# Consumer group lag for local group
print('=== 1. Consumer group: inv-device-server-local ===')
out, _ = run(f'docker exec {K} {BIN}/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group inv-device-server-local 2>&1')
print(out)

# Consumer group lag for cloud group
print('\n=== 2. Consumer group: inv-device-server-parser ===')
out, _ = run(f'docker exec {K} {BIN}/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group inv-device-server-parser 2>&1')
print(out)

# List all consumer groups
print('\n=== 3. All consumer groups ===')
out, _ = run(f'docker exec {K} {BIN}/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list 2>&1')
print(out)

# Topic details
print('\n=== 4. inv-telemetry topic ===')
out, _ = run(f'docker exec {K} {BIN}/kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic inv-telemetry 2>&1')
print(out)

# Get latest messages from inv-telemetry
print('\n=== 5. Latest messages from inv-telemetry ===')
out, _ = run(f'docker exec {K} {BIN}/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic inv-telemetry --from-beginning --max-messages 20 --timeout-ms 15000 2>&1')
lines = [l for l in out.split('\n') if l.strip() and not l.startswith('Processed')]
import re
msg_types = {}
for line in lines:
    match = re.search(r'"msg_type"\s*:\s*"([^"]+)"', line)
    if match:
        mt = match.group(1)
        msg_types[mt] = msg_types.get(mt, 0) + 1
print(f'Message types: {msg_types}')
print(f'Total lines: {len(lines)}')
for line in lines[:5]:
    print(f'  {line[:200]}')

# Bridge stats
print('\n=== 6. Bridge stats ===')
out, _ = run('wget -qO- --timeout=5 http://localhost:18088/stats 2>/dev/null')
print(out)

ssh.close()
print('\nDone!')
