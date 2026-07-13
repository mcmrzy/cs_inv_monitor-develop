import paramiko
import time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='REDACTED_ROTATE_CREDENTIAL')

# 清空日志并等待用户操作
print("请在浏览器中再次点击发送验证码...")
print("等待 10 秒...")
time.sleep(10)

# 获取最新日志（排除 DeviceStatus）
stdin, stdout, stderr = client.exec_command("echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S docker logs inv-api-server --since 2m 2>&1 | grep -v DeviceStatus | grep -v traces")
print("=== API Server 日志 ===")
print(stdout.read().decode())

# 获取网关日志
stdin, stdout, stderr = client.exec_command("echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S docker logs inv-api-gateway --since 2m 2>&1 | grep email")
print("\n=== 网关日志 ===")
print(stdout.read().decode())

client.close()
