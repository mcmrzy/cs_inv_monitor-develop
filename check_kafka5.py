#!/usr/bin/env python3
"""Check local parser consumer group lag."""
import paramiko

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('jiuxiaoyw.online', username='ubuntu', password='20040202sA', timeout=30)

def run(cmd):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=60)
    return stdout.read().decode().strip(), stderr.read().decode().strip()

K = 'inv-kafka'
BIN = '/opt/kafka/bin'

# Local parser group
print('=== 1. Consumer group: inv-device-server-local-parser ===')
out, _ = run(f'docker exec {K} {BIN}/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group inv-device-server-local-parser 2>&1')
print(out)

# Compare with cloud parser group
print('\n=== 2. Consumer group: inv-device-server-parser ===')
out, _ = run(f'docker exec {K} {BIN}/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group inv-device-server-parser 2>&1')
print(out)

# Get messages from the end of the topic (latest 20)
print('\n=== 3. Latest messages (tail) ===')
out, _ = run(f'docker exec {K} {BIN}/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic inv-telemetry --max-messages 20 --timeout-ms 15000 2>&1')
lines = [l for l in out.split('\n') if l.strip() and not l.startswith('Processed')]
import re
msg_types = {}
for line in lines:
    match = re.search(r'"msg_type"\s*:\s*"([^"]+)"', line)
    if match:
        mt = match.group(1)
        msg_types[mt] = msg_types.get(mt, 0) + 1
    # Also check for sn field
    sn_match = re.search(r'"sn"\s*:\s*"([^"]*)"', line)
print(f'Message types: {msg_types}')
print(f'Total lines: {len(lines)}')
for line in lines[:5]:
    if line.strip():
        print(f'  {line[:250]}')

# Bridge stats
print('\n=== 4. Bridge stats ===')
out, _ = run('wget -qO- --timeout=5 http://localhost:18088/stats 2>/dev/null')
print(out)

ssh.close()
print('\nDone!')
