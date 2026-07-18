import paramiko
from scp import SCPClient
import os
import time

LOCAL_PATH = r'd:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop'

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')
print('SSH connected')

# Upload fixed nginx.conf
print('Uploading nginx.conf...')
with SCPClient(client.get_transport()) as scp:
    scp.put(os.path.join(LOCAL_PATH, 'inv-admin-frontend', 'nginx.conf'), remote_path='/opt/inv-mqtt/inv-admin-frontend/nginx.conf')
print('Done')

# Rebuild frontend only
print('Rebuilding frontend...')
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose up -d --build inv-admin-frontend'")
print(stdout.read().decode())
err = stderr.read().decode()
if err:
    print(f'Error: {err}')

# Wait and check
time.sleep(30)
print('\nService status:')
stdin, stdout, stderr = client.exec_command('docker ps --format "table {{.Names}}\t{{.Status}}"')
print(stdout.read().decode())

client.close()
