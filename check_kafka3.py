#!/usr/bin/env python3
"""Check Kafka - find correct tool paths."""
import paramiko

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('jiuxiaoyw.online', username='ubuntu', password='20040202sA', timeout=30)

def run(cmd):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=60)
    return stdout.read().decode().strip(), stderr.read().decode().strip()

K = 'inv-kafka'

# Find Kafka image and tools
print('=== 1. Kafka image ===')
out, _ = run(f'docker inspect {K} --format "{{{{.Config.Image}}}}"')
print(out)

print('\n=== 2. Find kafka tools ===')
out, _ = run(f'docker exec {K} find / -name "kafka-consumer-groups*" -o -name "kafka-topics*" 2>/dev/null | head -10')
print(out if out else 'Not found with find')

print('\n=== 3. Check bin directory ===')
out, _ = run(f'docker exec {K} ls /opt/kafka/bin/ 2>/dev/null || docker exec {K} ls /usr/bin/kafka* 2>/dev/null || docker exec {K} ls /opt/bitnami/kafka/bin/ 2>/dev/null || echo "bin dirs not found"')
print(out)

print('\n=== 4. Try bitnami path ===')
out, _ = run(f'docker exec {K} /opt/bitnami/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list 2>&1')
print(out)

print('\n=== 5. Try confluent path ===')
out, _ = run(f'docker exec {K} /usr/bin/kafka-consumer-groups --bootstrap-server localhost:9092 --list 2>&1')
print(out)

print('\n=== 6. Check env ===')
out, _ = run(f'docker exec {K} env 2>/dev/null | grep -i kafka | head -10')
print(out)

# Bridge stats
print('\n=== 7. Bridge stats ===')
out, _ = run('wget -qO- --timeout=5 http://localhost:18088/stats 2>/dev/null')
print(out)

ssh.close()
print('\nDone!')
