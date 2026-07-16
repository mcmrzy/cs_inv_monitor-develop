#!/usr/bin/env python3
import paramiko
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('jiuxiaoyw.online', username='ubuntu', password='20040202sA', timeout=30)

def run(cmd):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=30)
    out = stdout.read().decode().strip()
    err = stderr.read().decode().strip()
    return out, err

# Connect bridge to the default bridge network (where EMQX is)
print('[1] Connecting bridge to default bridge network...')
out, err = run('docker network connect bridge mqtt-kafka-bridge 2>&1')
print(f'  {out or err or "connected"}')

# Verify connectivity from EMQX
print('[2] Testing EMQX -> Bridge connectivity...')
out, err = run('docker exec emqx-5.8.9 sh -c "wget -qO- --timeout=5 http://172.17.0.1:18088/health 2>&1 || curl -s --max-time 5 http://172.17.0.1:18088/health 2>&1 || echo FAILED"')
print(f'  {out}')

# Also try using the bridge container IP directly
print('[3] Getting bridge container IP on default network...')
out, _ = run("docker inspect mqtt-kafka-bridge --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}'")
print(f'  IPs: {out}')
ips = out.strip().split()
for ip in ips:
    ip = ip.strip()
    if ip:
        out2, _ = run(f'docker exec emqx-5.8.9 sh -c "wget -qO- --timeout=3 http://{ip}:18088/health 2>&1 || echo FAIL_{ip}"')
        print(f'  EMQX -> {ip}:18088 => {out2}')

# Wait and check stats
print('[4] Waiting 30s for messages...')
import time
time.sleep(30)
out, _ = run('wget -qO- --timeout=5 http://localhost:18088/stats 2>/dev/null')
print(f'  Stats: {out}')

# Check bridge logs
print('[5] Bridge logs:')
out, _ = run('docker logs mqtt-kafka-bridge --tail 5 2>&1')
print(f'  {out}')

ssh.close()
print('\nDone!')
