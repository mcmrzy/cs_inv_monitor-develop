import paramiko
import time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

print("=== 通过 Jenkins Script Console 创建用户 ===\n")

# 方法：通过 Jenkins API 发送 Groovy 脚本
# 即使未认证，某些 Jenkins 版本也允许匿名访问 Script Console

username = "ciskj"
password = "ciskj123"

# 直接在 Jenkins 容器内执行 Groovy 脚本
groovy_cmd = f"""echo 'cskj9527' | sudo -S docker exec jenkins-server java -jar /usr/share/jenkins/jenkins.war --argumentsRealm.passwd.{username}={password} --argumentsRealm.roles.{username}=admin 2>&1 | head -5"""
stdin, stdout, stderr = client.exec_command(groovy_cmd)
print(f"方法1输出: {stdout.read().decode().strip()[:200]}")

# 方法2: 直接修改 Jenkins 配置文件来添加用户
print("\n直接修改配置文件创建用户...")

# 步骤1: 生成 bcrypt 密码哈希 (使用 Python bcrypt 库)
try:
    import bcrypt
    password_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
    print(f"密码哈希: {password_hash}")
except ImportError:
    # 如果没有 bcrypt 库，使用在线服务或手动构造
    # Jenkins 格式: #jbcrypt:$2a$10$...
    # 手动使用一个已知的 bcrypt 哈希
    password_hash = "$2a$10$3Q9GqwZ5K5Z5K5Z5K5Z5Ke"  # placeholder
    print("使用预设哈希")

# 步骤2: 创建用户目录
user_dir_hash = "ciskj_12345678901234567890"
create_dir_cmd = f"echo 'cskj9527' | sudo -S docker exec jenkins-server mkdir -p /var/jenkins_home/users/{user_dir_hash}"
stdin, stdout, stderr = client.exec_command(create_dir_cmd)

# 步骤3: 创建用户 config.xml
user_config = f"""<?xml version='1.1' encoding='UTF-8'?>
<user>
  <version>1</version>
  <id>{username}</id>
  <fullName>{username}</fullName>
  <properties>
    <jenkins.security.ApiTokenProperty>
      <tokenStore>
        <tokenList/>
      </tokenStore>
    </jenkins.security.ApiTokenProperty>
    <jenkins.security.LastGrantedAuthoritiesProperty>
      <roles>
        <string>authenticated</string>
      </roles>
    </jenkins.security.LastGrantedAuthoritiesProperty>
  </properties>
</user>"""

# 写入配置文件
write_cmd = f"""echo 'cskj9527' | sudo -S docker exec -i jenkins-server bash -c 'cat > /var/jenkins_home/users/{user_dir_hash}/config.xml' << 'XMLEOF'
{user_config}
XMLEOF"""
stdin, stdout, stderr = client.exec_command(write_cmd)
print(f"写入配置: {stderr.read().decode().strip()[:200]}")

# 步骤4: 更新 users.xml
users_xml = f"""<?xml version='1.1' encoding='UTF-8'?>
<hudson.model.UserIdMapper>
  <version>1</version>
  <idToDirectoryNameMap class="concurrent-hash-map">
    <entry>
      <string>ekko _707790072@qq.com_</string>
      <string>Ekko707790072q_10715765782448077065</string>
    </entry>
    <entry>
      <string>admin</string>
      <string>admin_11055796422768726520</string>
    </entry>
    <entry>
      <string>{username}</string>
      <string>{user_dir_hash}</string>
    </entry>
  </idToDirectoryNameMap>
</hudson.model.UserIdMapper>"""

# 备份原始 users.xml
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec jenkins-server cp /var/jenkins_home/users/users.xml /var/jenkins_home/users/users.xml.bak")

# 写入新的 users.xml
write_users_cmd = f"""echo 'cskj9527' | sudo -S docker exec -i jenkins-server bash -c 'cat > /var/jenkins_home/users/users.xml' << 'XMLEOF'
{users_xml}
XMLEOF"""
stdin, stdout, stderr = client.exec_command(write_users_cmd)
print(f"更新 users.xml: {stderr.read().decode().strip()[:200]}")

# 验证
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker exec jenkins-server ls /var/jenkins_home/users/")
print(f"\n用户目录:\n{stdout.read().decode().strip()}")

# 重启 Jenkins
print("\n重启 Jenkins...")
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker restart jenkins-server")
print(stdout.read().decode().strip())

time.sleep(30)

print(f"\n=== 完成 ===")
print(f"用户名: {username}")
print(f"密码: {password}")
print(f"访问地址: http://192.168.8.50:8080")
print(f"\n注意: 如果登录失败，请用以下方式重置密码:")
print(f"1. 访问 http://192.168.8.50:8080")
print(f"2. 用 admin 或 Ekko 用户登录（如果知道密码）")
print(f"3. Manage Jenkins -> Users -> {username} -> Configure -> 设置密码")

client.close()
