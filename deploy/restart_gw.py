import paramiko
import time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

print("重启 API 网关以刷新权限缓�?..")
stdin, stdout, stderr = client.exec_command(
    "echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S bash -c 'cd /opt/inv-mqtt/deploy && docker compose restart inv-api-gateway'"
)
print(stdout.read().decode())

time.sleep(15)

stdin, stdout, stderr = client.exec_command(
    "echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker ps --format '{{.Names}}: {{.Status}}' | grep gateway"
)
print(f"状�? {stdout.read().decode().strip()}")

client.close()
print("完成，请刷新浏览器重�?)
