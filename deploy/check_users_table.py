import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 查看 users 表结�?
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c '\\d users'")
print("=== users 表结�?===")
print(stdout.read().decode())

client.close()
