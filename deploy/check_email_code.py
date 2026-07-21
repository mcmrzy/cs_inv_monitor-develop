import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 查看 API Server 中邮件相关代�?
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-api-server sh -c 'find /app -name \"*.go\" | head -20'")
print("=== Go 文件列表 ===")
print(stdout.read().decode())

# 搜索 send-email-code 相关代码
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-api-server sh -c 'grep -r \"send-email-code\\|SendEmail\\|email.*code\" /app/ --include=\"*.go\" 2>/dev/null | head -20'")
print("\n=== 邮件相关代码 ===")
print(stdout.read().decode())

client.close()
