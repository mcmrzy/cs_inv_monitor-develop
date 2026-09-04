import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 检查监听的端口
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S ss -tlnp 2>/dev/null || netstat -tlnp")
print('=== 服务器监听端�?===')
print(stdout.read().decode())

# 检查防火墙状�?
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S ufw status 2>/dev/null || echo 'ufw not available'")
print('=== 防火墙状�?===')
print(stdout.read().decode())

# 检�?iptables
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S iptables -L -n --line-numbers 2>/dev/null | head -40")
print('=== iptables 规则 ===')
print(stdout.read().decode())

client.close()
