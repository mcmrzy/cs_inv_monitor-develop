#!/usr/bin/env python3
import paramiko
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('jiuxiaoyw.online', username='ubuntu', password='20040202sA', timeout=30)

def run(cmd):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=30)
    return stdout.read().decode().strip(), stderr.read().decode().strip()

print('=== Bridge Logs ===')
out, _ = run('docker logs mqtt-kafka-bridge --tail 20 2>&1')
print(out)

print('\n=== EMQX -> Bridge health ===')
out, _ = run('docker exec emqx-5.8.9 wget -qO- --timeout=5 http://172.17.0.1:18088/health 2>&1')
print(out if out else 'EMQX cannot reach bridge via 172.17.0.1:18088')

print('\n=== Bridge network ===')
out, _ = run("docker inspect mqtt-kafka-bridge --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'")
print(out)

print('\n=== EMQX network ===')
out, _ = run("docker inspect emqx-5.8.9 --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'")
print(out)

print('\n=== Bridge stats ===')
out, _ = run('wget -qO- --timeout=5 http://localhost:18088/stats 2>/dev/null')
print(out)

print('\n=== Kafka connectivity ===')
out, _ = run('docker exec mqtt-kafka-bridge wget -qO- --timeout=5 http://localhost:18088/health 2>/dev/null || echo "bridge internal health failed"')
print(out)

ssh.close()
