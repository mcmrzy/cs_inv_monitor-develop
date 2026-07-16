#!/usr/bin/env python3
"""Deploy mqtt-kafka-bridge to production server."""
import paramiko
import sys

HOST = "jiuxiaoyw.online"
USER = "ubuntu"
PASS = "20040202sA"

BINARY_PATH = r"D:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop\mqtt-kafka-bridge\mqtt-kafka-bridge-linux"
CONFIG_PATH = r"D:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop\mqtt-kafka-bridge\config.docker.yaml"

def run_cmd(ssh, cmd, desc=""):
    if desc:
        print(f"  > {desc}")
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=60)
    out = stdout.read().decode().strip()
    err = stderr.read().decode().strip()
    if out:
        print(f"  {out}")
    if err:
        # Filter out Docker warnings
        for line in err.split('\n'):
            if line and 'warning' not in line.lower() and 'level=' not in line.lower():
                print(f"  ERR: {line}")
    return out

def main():
    print(f"[1/7] Connecting to {HOST}...")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, username=USER, password=PASS, timeout=30)
    sftp = ssh.open_sftp()
    print("  Connected!")

    print("[2/7] Uploading binary (8MB)...")
    sftp.put(BINARY_PATH, "/tmp/mqtt-kafka-bridge")
    print("  Binary uploaded.")

    print("[3/7] Uploading config...")
    sftp.put(CONFIG_PATH, "/tmp/mqtt-kafka-bridge-config.yaml")
    print("  Config uploaded.")
    sftp.close()

    print("[4/7] Finding Kafka Docker network...")
    network = run_cmd(ssh, "docker inspect inv-kafka --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null || echo 'bridge'")
    network = network.strip() or "bridge"
    print(f"  Kafka network: {network}")

    print("[5/7] Stopping and removing old bridge...")
    run_cmd(ssh, "docker stop mqtt-kafka-bridge 2>/dev/null; docker rm mqtt-kafka-bridge 2>/dev/null; echo 'cleaned'")

    print("[6/7] Starting new bridge...")
    run_cmd(ssh, "chmod +x /tmp/mqtt-kafka-bridge")
    cmd = (
        f"docker run -d --name mqtt-kafka-bridge "
        f"--network {network} "
        f"--restart=unless-stopped "
        f"-p 18088:18088 "
        f"-v /tmp/mqtt-kafka-bridge:/app/mqtt-kafka-bridge:ro "
        f"-v /tmp/mqtt-kafka-bridge-config.yaml:/app/config.yaml:ro "
        f"alpine:3.19 /app/mqtt-kafka-bridge /app/config.yaml"
    )
    run_cmd(ssh, cmd, "Starting container...")

    print("[7/7] Verifying deployment...")
    import time
    time.sleep(5)
    run_cmd(ssh, "docker ps --filter name=mqtt-kafka-bridge --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'", "Container status:")
    run_cmd(ssh, "docker logs mqtt-kafka-bridge --tail 10 2>&1", "Recent logs:")
    run_cmd(ssh, "wget -qO- --timeout=5 http://localhost:18088/health 2>/dev/null || echo 'health check failed'", "Health check:")
    run_cmd(ssh, "wget -qO- --timeout=5 http://localhost:18088/stats 2>/dev/null || echo 'stats check failed'", "Stats:")

    ssh.close()
    print("\nDeployment complete!")

if __name__ == "__main__":
    main()
