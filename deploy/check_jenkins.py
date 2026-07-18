import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 获取 Jenkins 初始密码
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec jenkins-server cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null")
out = stdout.read().decode().strip()
err = stderr.read().decode().strip()
if out:
    print(f"Jenkins 初始密码: {out}")
else:
    print(f"获取失败: {err}")

# 检�?Jenkins 是否已配置用�?
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec jenkins-server ls /var/jenkins_home/users/ 2>/dev/null")
print(f"\n用户目录: {stdout.read().decode().strip()}")

# 检�?Jenkins 配置
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec jenkins-server cat /var/jenkins_home/config.xml 2>/dev/null | grep -A2 'useSecurity\\|authorizationStrategy'")
print(f"\n安全配置:\n{stdout.read().decode().strip()[:500]}")

client.close()
