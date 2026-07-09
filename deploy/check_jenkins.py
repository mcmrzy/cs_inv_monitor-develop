import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

# 获取 Jenkins 初始密码
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec jenkins-server cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null")
out = stdout.read().decode().strip()
err = stderr.read().decode().strip()
if out:
    print(f"Jenkins 初始密码: {out}")
else:
    print(f"获取失败: {err}")

# 检查 Jenkins 是否已配置用户
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec jenkins-server ls /var/jenkins_home/users/ 2>/dev/null")
print(f"\n用户目录: {stdout.read().decode().strip()}")

# 检查 Jenkins 配置
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec jenkins-server cat /var/jenkins_home/config.xml 2>/dev/null | grep -A2 'useSecurity\\|authorizationStrategy'")
print(f"\n安全配置:\n{stdout.read().decode().strip()[:500]}")

client.close()
