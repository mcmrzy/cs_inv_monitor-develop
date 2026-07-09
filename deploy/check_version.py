import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.8.50', username='cskj', password='cskj9527')

# 检查 Docker 镜像构建时间
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker inspect inv-api-server --format '{{.Created}}'")
print("API Server 镜像构建时间:", stdout.read().decode().strip())

# 检查镜像来源
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker inspect inv-api-server --format '{{.Config.Labels}}'")
print("镜像标签:", stdout.read().decode().strip()[:200])

# 通过网关测试（模拟浏览器请求）
stdin, stdout, stderr = client.exec_command("""curl -s -X POST 'http://127.0.0.1:8888/api/v1/auth/send-email-code' -H 'Content-Type: application/json' -H 'X-Captcha-Token: test123' -H 'Origin: http://192.168.8.50:3000' -d '{"email":"sunhaoyu0221@qq.com","type":"register"}' 2>&1""")
print("\n通过网关测试:", stdout.read().decode())

# 查看网关日志
stdin, stdout, stderr = client.exec_command("echo 'cskj9527' | sudo -S docker logs inv-api-gateway --tail 5 2>&1 | grep -i email")
print("\n网关日志:", stdout.read().decode())

client.close()
