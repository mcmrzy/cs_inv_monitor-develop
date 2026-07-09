import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

# 查看用户配置
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec jenkins-server cat /var/jenkins_home/users/users.xml")
print(stdout.read().decode())

# 查看 admin 用户详细信息
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec jenkins-server cat /var/jenkins_home/users/admin_11055796422768726520/config.xml 2>/dev/null | head -30")
print("\n=== admin 用户配置 ===")
print(stdout.read().decode())

# 查看 Ekko 用户详细信息
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec jenkins-server cat /var/jenkins_home/users/Ekko707790072q_10715765782448077065/config.xml 2>/dev/null | head -30")
print("\n=== Ekko 用户配置 ===")
print(stdout.read().decode())

client.close()
