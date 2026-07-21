import paramiko
import os

server = os.environ.get("DEPLOY_SERVER", "example.invalid")
username = os.environ.get("DEPLOY_USERNAME", "deploy")
password = os.environ["DEPLOY_PASSWORD"]

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(server, username=username, password=password)
stdin, stdout, stderr = client.exec_command('docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"')
print(stdout.read().decode())
client.close()
