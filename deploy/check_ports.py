import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

# 检查监听的端口
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S ss -tlnp 2>/dev/null || netstat -tlnp")
print('=== 服务器监听端口 ===')
print(stdout.read().decode())

# 检查防火墙状态
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S ufw status 2>/dev/null || echo 'ufw not available'")
print('=== 防火墙状态 ===')
print(stdout.read().decode())

# 检查 iptables
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S iptables -L -n --line-numbers 2>/dev/null | head -40")
print('=== iptables 规则 ===')
print(stdout.read().decode())

client.close()
