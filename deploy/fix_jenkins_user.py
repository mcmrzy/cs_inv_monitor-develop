import paramiko
import time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 生成 bcrypt 密码哈希
import bcrypt
password = "CHANGE_ME_JENKINS_PASSWORD"
hashed = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
print(f"密码哈希: {hashed}")

# 用户配置文件（包含密码）
user_config = f"""<?xml version='1.1' encoding='UTF-8'?>
<user>
  <version>2</version>
  <id>ciskj</id>
  <fullName>ciskj</fullName>
  <properties>
    <jenkins.security.ApiTokenProperty>
      <tokenStore>
        <tokenList/>
      </tokenStore>
    </jenkins.security.ApiTokenProperty>
    <hudson.security.HudsonPrivateSecurityRealm_-Details>
      <passwordHash>#jbcrypt:{hashed}</passwordHash>
    </hudson.security.HudsonPrivateSecurityRealm_-Details>
    <jenkins.security.LastGrantedAuthoritiesProperty>
      <roles>
        <string>authenticated</string>
      </roles>
    </jenkins.security.LastGrantedAuthoritiesProperty>
  </properties>
</user>"""

# 写入临时文件
tmp_file = "/tmp/jenkins_ciskj_config.xml"
sftp = client.open_sftp()
with sftp.file(tmp_file, 'w') as f:
    f.write(user_config)
sftp.close()
print("配置文件已写入临时目�?)

# 复制�?Jenkins 容器
cmd = f"echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker cp {tmp_file} jenkins-server:/var/jenkins_home/users/ciskj_12345678901234567890/config.xml"
stdin, stdout, stderr = client.exec_command(cmd)
err = stderr.read().decode().strip()
print(f"复制到容�? {'OK' if not err or 'sudo' in err else err}")

# 重启 Jenkins
print("重启 Jenkins...")
stdin, stdout, stderr = client.exec_command("echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker restart jenkins-server")
print(stdout.read().decode().strip())

print("\n等待启动...")
time.sleep(40)

# 清理
client.exec_command(f"rm -f {tmp_file}")

print(f"\n=== 完成 ===")
print(f"用户�? ciskj")
print(f"密码: CHANGE_ME_JENKINS_PASSWORD")
print(f"访问: http://example.invalid:8080")

client.close()
