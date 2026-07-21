import paramiko
import time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 清空日志缓冲 - 先记录当前时间戳
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker logs inv-api-server --tail 1 2>&1 | grep -o '\"ts\":[0-9.]*'")
last_ts = stdout.read().decode().strip()
print(f"当前最后日志时间戳: {last_ts}")
print("\n请现在在浏览器中点击发送验证码...")
print("等待 15 秒后抓取日志...")
time.sleep(15)

# 获取新日�?
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker logs inv-api-server --since 1m 2>&1 | grep -v DeviceStatus")
print("\n=== API Server 新日�?===")
print(stdout.read().decode()[:3000])

# 网关日志
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker logs inv-api-gateway --since 1m 2>&1 | grep email")
print("\n=== 网关邮件日志 ===")
print(stdout.read().decode())

client.close()
