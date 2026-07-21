import paramiko
import time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

stdin, stdout, stderr = client.exec_command(
    "echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose restart inv-api-gateway'"
)
stdout.read()
time.sleep(15)

stdin, stdout, stderr = client.exec_command(
    "echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker ps --format '{{.Names}}: {{.Status}}' | grep inv"
)
print(stdout.read().decode())

client.close()
print("API 网关已重�?)
