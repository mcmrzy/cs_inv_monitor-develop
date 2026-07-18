import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')
stdin, stdout, stderr = client.exec_command('docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"')
print(stdout.read().decode())
client.close()
