import paramiko
import time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

stdin, stdout, stderr = client.exec_command(
    "echo 'cskj9527' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose restart inv-api-gateway'"
)
stdout.read()
time.sleep(15)

stdin, stdout, stderr = client.exec_command(
    "echo 'cskj9527' | sudo -S docker ps --format '{{.Names}}: {{.Status}}' | grep inv"
)
print(stdout.read().decode())

client.close()
print("API 网关已重启")
