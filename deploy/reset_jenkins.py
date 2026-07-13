import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='REDACTED_ROTATE_CREDENTIAL')

# 重置 admin 密码为 admin123
new_password = "admin123"
cmd = f"echo 'REDACTED_ROTATE_CREDENTIAL' | sudo -S docker exec jenkins-server bash -c \"java -jar /usr/share/jenkins/jenkins.war --params=hudson.security.HudsonPrivateSecurityRealm.createAccount=admin:{new_password}\" 2>/dev/null || echo 'Method1 failed'"

# 使用 Jenkins 脚本控制台重置密码
script_console = """
import jenkins.model.*
import hudson.security.*

def instance = Jenkins.getInstance()
def realm = instance.getSecurityRealm()

// 删除旧用户并重新创建
realm.createAccount("admin", "admin123")
instance.save()
println("Password reset successfully")
"""

# 通过 Jenkins CLI 或 Groovy 脚本重置
# 方法：直接修改用户配置文件中的密码哈希
import hashlib
import uuid

# 生成 Jenkins 格式的密码哈希
password = "admin123"
salt = uuid.uuid4().hex[:16]
# Jenkins 使用 bcrypt 或者自定义哈希
# 最简单的方式是通过 Groovy 脚本控制台

print("尝试通过 Jenkins API 重置密码...")
print("\n由于 Jenkins 需要先登录才能使用 API，")
print("建议你直接访问 Jenkins 登录页面：")
print("\n  http://192.168.8.50:8080")
print("\n然后尝试以下操作：")
print("1. 如果知道 Ekko 用户的密码，用它登录")
print("2. 登录后进入 Manage Jenkins → Users → admin → Configure → 修改密码")
print("\n或者，我可以帮你重启 Jenkins 并跳过安全检查来重置密码。")
print("是否要这样做？")

client.close()
