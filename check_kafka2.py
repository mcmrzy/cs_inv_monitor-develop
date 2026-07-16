#!/usr/bin/env python3
"""Check Kafka consumer group lag using inv-kafka container."""
import paramiko

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('jiuxiaoyw.online', username='ubuntu', password='20040202sA', timeout=30)

def run(cmd):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=60)
    return stdout.read().decode().strip(), stderr.read().decode().strip()

K = 'inv-kafka'

# Consumer group lag for local group
print('=== 1. Consumer group: inv-device-server-local ===')
out, _ = run(f'docker exec {K} kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group inv-device-server-local 2>&1')
print(out)

# Consumer group lag for cloud group
print('\n=== 2. Consumer group: inv-device-server-parser ===')
out, _ = run(f'docker exec {K} kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group inv-device-server-parser 2>&1')
print(out)

# List all consumer groups
print('\n=== 3. All consumer groups ===')
out, _ = run(f'docker exec {K} kafka-consumer-groups --bootstrap-server localhost:9092 --list 2>&1')
print(out)

# Topic details
print('\n=== 4. inv-telemetry topic ===')
out, _ = run(f'docker exec {K} kafka-topics --bootstrap-server localhost:9092 --describe --topic inv-telemetry 2>&1')
print(out)

# Get latest messages from inv-telemetry (last 20)
print('\n=== 5. Latest 20 messages from inv-telemetry ===')
out, _ = run(f'docker exec {K} kafka-console-consumer --bootstrap-server localhost:9092 --topic inv-telemetry --from-beginning --max-messages 20 --timeout-ms 15000 2>&1')
# Extract msg_type from each message
lines = out.split('\n')
msg_types = {}
for line in lines:
    if 'msg_type' in line:
        # Find msg_type value
        import re
        match = re.search(r'"msg_type"\s*:\s*"([^"]+)"', line)
        if match:
            mt = match.group(1)
            msg_types[mt] = msg_types.get(mt, 0) + 1
print(f'Message types found: {msg_types}')
print(f'Total messages: {len([l for l in lines if l.strip()])}')
# Show first 3 messages
for line in lines[:3]:
    if line.strip():
        print(f'  {line[:200]}')

# Bridge stats
print('\n=== 6. Bridge stats ===')
out, _ = run('wget -qO- --timeout=5 http://localhost:18088/stats 2>/dev/null')
print(out)

ssh.close()
print('\nDone!')
