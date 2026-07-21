import paramiko
import time
import os

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

username = "ciskj"
password = "CHANGE_ME_JENKINS_PASSWORD"
user_dir = "ciskj_12345678901234567890"
tmp_dir = "/tmp/jenkins_user"

print("=== 创建 Jenkins 用户 ===\n")

# 步骤1: 在主机上创建临时文件
print("[1/5] 创建临时配置文件...")
client.exec_command(f"mkdir -p {tmp_dir}/{user_dir}")

# 用户 config.xml
user_config = f"""<?xml version='1.1' encoding='UTF-8'?>
<user>
  <version>2</version>
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

# 写入到主机临时目�?
sftp = client.open_sftp()
with sftp.file(f"{tmp_dir}/{user_dir}/config.xml", 'w') as f:
    f.write(user_config)
print("  用户配置文件已写�?)

# users.xml
users_xml = """<?xml version='1.1' encoding='UTF-8'?>
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
      <string>ciskj</string>
      <string>ciskj_12345678901234567890</string>
    </entry>
  </idToDirectoryNameMap>
</hudson.model.UserIdMapper>"""

with sftp.file(f"{tmp_dir}/users.xml", 'w') as f:
    f.write(users_xml)
print("  users.xml 已写�?)
sftp.close()

# 步骤2: �?docker cp 复制文件到容�?
print("\n[2/5] 复制文件�?Jenkins 容器...")

# 复制用户配置
cmd = f"echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker cp {tmp_dir}/{user_dir}/config.xml jenkins-server:/var/jenkins_home/users/{user_dir}/config.xml"
stdin, stdout, stderr = client.exec_command(cmd)
err = stderr.read().decode().strip()
print(f"  复制用户配置: {'OK' if not err or 'sudo' in err else err}")

# 复制 users.xml
cmd = f"echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker cp {tmp_dir}/users.xml jenkins-server:/var/jenkins_home/users/users.xml"
stdin, stdout, stderr = client.exec_command(cmd)
err = stderr.read().decode().strip()
print(f"  复制 users.xml: {'OK' if not err or 'sudo' in err else err}")

# 步骤3: 验证
print("\n[3/5] 验证文件...")
stdin, stdout, stderr = client.exec_command(f"echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec jenkins-server ls /var/jenkins_home/users/")
print(f"  用户目录: {stdout.read().decode().strip()}")

stdin, stdout, stderr = client.exec_command(f"echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec jenkins-server cat /var/jenkins_home/users/{user_dir}/config.xml | head -5")
print(f"  配置文件: {stdout.read().decode().strip()[:100]}")

# 步骤4: 重启 Jenkins
print("\n[4/5] 重启 Jenkins...")
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker restart jenkins-server")
print(f"  {stdout.read().decode().strip()}")

print("\n[5/5] 等待启动...")
time.sleep(40)

# 清理临时文件
client.exec_command(f"rm -rf {tmp_dir}")

print(f"\n=== 完成 ===")
print(f"用户�? {username}")
print(f"密码: {password}")
print(f"访问地址: http://example.invalid:8080")

client.close()
