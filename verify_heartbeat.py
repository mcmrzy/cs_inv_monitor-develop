#!/usr/bin/env python3
"""Check heartbeat results after offset reset."""
import subprocess
import time

def docker_exec(container, cmd):
    result = subprocess.run(
        ['docker', 'exec', container, 'sh', '-c', cmd],
        capture_output=True, text=True, timeout=30
    )
    return result.stdout.strip()

print('=== 1. Heartbeat references in device-server logs ===')
out = docker_exec('inv-device-server', 'grep -c "heartbeat" /app/logs/device-server.log 2>/dev/null || echo 0')
print(f'Heartbeat count: {out}')

out = docker_exec('inv-device-server', 'grep "heartbeat" /app/logs/device-server.log | tail -5')
print(out if out else 'No heartbeat entries')

print('\n=== 2. Message types received ===')
out = docker_exec('inv-device-server', 'grep "handleTelemetry called" /app/logs/device-server.log | tail -20')
for line in out.split('\n')[-10:]:
    if 'msg_type' in line:
        print(f'  {line[:200]}')

print('\n=== 3. device_telemetry_3min ===')
out = docker_exec('inv-postgres', "psql -U postgres -d inv_mqtt -c \"SELECT COUNT(*) FROM device_telemetry_3min WHERE device_sn = 'H1CNA00135000014'\"")
print(out)

print('\n=== 4. Ingest errors ===')
out = docker_exec('inv-postgres', "psql -U postgres -d inv_mqtt -c \"SELECT error_code, COUNT(*) FROM device_ingest_errors GROUP BY error_code\"")
print(out)

print('\n=== 5. Latest device-server logs ===')
out = docker_exec('inv-device-server', 'tail -15 /app/logs/device-server.log')
print(out[-2000:] if out else 'No logs')

print('\nDone!')
