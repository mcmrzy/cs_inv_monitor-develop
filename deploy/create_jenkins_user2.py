import paramiko
import time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

print("=== 创建 Jenkins 新用�?===\n")

username = "ciskj"
password = "CHANGE_ME_JENKINS_PASSWORD"

# 创建 init.groovy.d 目录
print("[1/4] 创建脚本目录...")
cmd = "echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec jenkins-server mkdir -p /var/jenkins_home/init.groovy.d"
stdin, stdout, stderr = client.exec_command(cmd)
print(stderr.read().decode().strip())

# 写入 Groovy 脚本
print("[2/4] 写入用户创建脚本...")
groovy_script = """
import jenkins.model.*
import hudson.security.*

def instance = Jenkins.getInstance()
def realm = instance.getSecurityRealm()

if (realm instanceof HudsonPrivateSecurityRealm) {
    realm.createAccount("ciskj", "CHANGE_ME_JENKINS_PASSWORD")
    instance.save()
    println("User 'ciskj' created successfully")
} else {
    println("Security realm is not HudsonPrivateSecurityRealm")
}
"""

# 使用 heredoc 方式写入
write_cmd = f"""echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec jenkins-server bash -c "cat > /var/jenkins_home/init.groovy.d/create_user.groovy << 'GROOVYEOF'
{groovy_script}
GROOVYEOF" """
stdin, stdout, stderr = client.exec_command(write_cmd)
err = stderr.read().decode().strip()
if err:
    print(f"写入错误: {err}")

# 验证文件是否写入
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec jenkins-server cat /var/jenkins_home/init.groovy.d/create_user.groovy")
content = stdout.read().decode().strip()
print(f"脚本内容验证: {'OK' if 'createAccount' in content else 'FAILED'}")

# 重启 Jenkins
print("\n[3/4] 重启 Jenkins...")
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker restart jenkins-server")
print(stdout.read().decode().strip())

# 等待启动
print("\n[4/4] 等待 Jenkins 启动...")
time.sleep(45)

# 检查用�?
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec jenkins-server ls /var/jenkins_home/users/")
users = stdout.read().decode().strip()
print(f"\n用户列表:\n{users}")

# 删除脚本避免重复创建
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec jenkins-server rm -f /var/jenkins_home/init.groovy.d/create_user.groovy")

if 'ciskj' in users:
    print(f"\n=== 创建成功 ===")
    print(f"用户�? {username}")
    print(f"密码: {password}")
    print(f"访问地址: http://example.invalid:8080")
else:
    print("\n=== 可能需要等待更长时间，请稍后检�?===")

client.close()
