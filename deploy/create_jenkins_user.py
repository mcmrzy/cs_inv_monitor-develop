import paramiko
import time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

print("=== 创建 Jenkins 新用�?===\n")

# 新用户信�?
username = "ciskj"
password = "CHANGE_ME_JENKINS_PASSWORD"
email = "ciskj@163.com"
fullname = "ciskj"

# Jenkins 密码哈希格式 (bcrypt)
# 使用 Jenkins 内置方式生成哈希
print("[1/3] 生成密码哈希...")
gen_hash_cmd = f"""echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec jenkins-server java -cp /usr/share/jenkins/jenkins.war:/usr/share/jenkins/lib/*.jar hudson.security.HudsonPrivateSecurityRealm '{password}' 2>/dev/null || echo 'fallback'"""
stdin, stdout, stderr = client.exec_command(gen_hash_cmd)
hash_result = stdout.read().decode().strip()

if hash_result and hash_result != 'fallback':
    password_hash = hash_result
else:
    # 使用 Jenkins Groovy 控制台生成哈�?- 但需要认�?
    # 直接使用标准 bcrypt 格式
    import subprocess
    # 手动构�?Jenkins 兼容的密码哈�?
    # Jenkins 使用 BCryptPasswordEncoder
    # 格式: #jbcrypt:$2a$10$...
    password_hash = "PLACEHOLDER"

print(f"[2/3] 创建用户配置文件...")

# 创建用户�?Groovy init script
init_script = f'''
import jenkins.model.*
import hudson.security.*

def instance = Jenkins.getInstance()
def realm = instance.getSecurityRealm()

if (realm instanceof HudsonPrivateSecurityRealm) {{
    realm.createAccount("{username}", "{password}")
    instance.save()
    println("User '{username}' created successfully")
}} else {{
    println("Security realm is not HudsonPrivateSecurityRealm")
}}
'''

# 写入 Groovy 脚本�?Jenkins init 目录
write_script_cmd = f"""echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec jenkins-server bash -c 'cat > /var/jenkins_home/init.groovy.d/create_user.groovy << GROOVYEOF
{init_script}
GROOVYEOF'"""
stdin, stdout, stderr = client.exec_command(write_script_cmd)
print(f"写入脚本: {stdout.read().decode().strip()}")
print(f"错误: {stderr.read().decode().strip()}")

# 重启 Jenkins 使脚本生�?
print("\n[3/3] 重启 Jenkins...")
restart_cmd = "echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker restart jenkins-server"
stdin, stdout, stderr = client.exec_command(restart_cmd)
print(stdout.read().decode().strip())

# 等待 Jenkins 启动
print("\n等待 Jenkins 启动...")
time.sleep(30)

# 检�?Jenkins 状�?
stdin, stdout, stderr = client.exec_command('docker ps --format "{{.Names}}: {{.Status}}" | grep jenkins')
print(f"Jenkins 状�? {stdout.read().decode().strip()}")

# 检查用户是否创建成�?
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec jenkins-server ls /var/jenkins_home/users/")
print(f"用户列表: {stdout.read().decode().strip()}")

# 删除 init script 避免重复创建
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec jenkins-server rm -f /var/jenkins_home/init.groovy.d/create_user.groovy")

print(f"\n=== 完成 ===")
print(f"用户�? {username}")
print(f"密码: {password}")
print(f"访问地址: http://example.invalid:8080")

client.close()
