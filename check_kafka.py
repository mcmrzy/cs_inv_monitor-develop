#!/usr/bin/env python3
"""Check Kafka consumer group lag and topic details on production server."""
import paramiko

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('jiuxiaoyw.online', username='ubuntu', password='20040202sA', timeout=30)

def run(cmd):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=30)
    return stdout.read().decode().strip(), stderr.read().decode().strip()

# Find Kafka container
print('=== 1. Kafka container ===')
out, _ = run('docker ps --format "{{.Names}}" | grep -i kafka')
print(out)

kafka_container = out.strip().split('\n')[0] if out else ''
print(f'Using container: {kafka_container}')

if kafka_container:
    # Consumer group lag for local group
    print('\n=== 2. Consumer group: inv-device-server-local ===')
    out, _ = run(f'docker exec {kafka_container} kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group inv-device-server-local 2>&1')
    print(out)

    # Consumer group lag for cloud group
    print('\n=== 3. Consumer group: inv-device-server-parser ===')
    out, _ = run(f'docker exec {kafka_container} kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group inv-device-server-parser 2>&1')
    print(out)

    # List all consumer groups
    print('\n=== 4. All consumer groups ===')
    out, _ = run(f'docker exec {kafka_container} kafka-consumer-groups --bootstrap-server localhost:9092 --list 2>&1')
    print(out)

    # Topic details
    print('\n=== 5. inv-telemetry topic ===')
    out, _ = run(f'docker exec {kafka_container} kafka-topics --bootstrap-server localhost:9092 --describe --topic inv-telemetry 2>&1')
    print(out)

    # Get latest messages from inv-telemetry (last 10)
    print('\n=== 6. Latest messages from inv-telemetry ===')
    out, _ = run(f'docker exec {kafka_container} kafka-console-consumer --bootstrap-server localhost:9092 --topic inv-telemetry --from-beginning --max-messages 5 --timeout-ms 10000 2>&1')
    print(out[-3000:] if len(out) > 3000 else out)

    # Check bridge stats
    print('\n=== 7. Bridge stats ===')
    out, _ = run('wget -qO- --timeout=5 http://localhost:18088/stats 2>/dev/null')
    print(out)

    # Check what msg_types are in the topic
    print('\n=== 8. Message types in topic ===')
    out, _ = run(f'docker exec {kafka_container} kafka-console-consumer --bootstrap-server localhost:9092 --topic inv-telemetry --from-beginning --max-messages 20 --timeout-ms 10000 2>&1 | grep -oP "msg_type[^,]*" | sort | uniq -c | sort -rn')
    print(out if out else 'Could not extract msg_types')

ssh.close()
print('\nDone!')
