import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('example.invalid', username='cskj', password='CHANGE_ME_ROTATE_CREDENTIAL')

# 添加 email �?
cmd = """echo 'CHANGE_ME_ROTATE_CREDENTIAL' | sudo -S docker exec inv-postgres psql -U postgres -d inv_mqtt -c "ALTER TABLE users ADD COLUMN IF NOT EXISTS email VARCHAR(100); SELECT column_name FROM information_schema.columns WHERE table_name='users' AND column_name='email';" """
stdin, stdout, stderr = client.exec_command(cmd)
out = stdout.read().decode()
err = stderr.read().decode()
print(out)
if err and 'sudo' not in err:
    print(f"Error: {err}")

client.close()
