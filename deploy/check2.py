import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='REDACTED_ROTATE_CREDENTIAL')
stdin, stdout, stderr = client.exec_command('docker logs inv-admin-frontend --tail 30 2>&1')
print(stdout.read().decode())
client.close()
