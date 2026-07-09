import socket

ports = [22, 80, 443, 3000, 3389, 5000, 8080, 8081, 8443, 8888, 9090, 42222, 46666, 50000]
target = "175.0.55.107"

print(f"扫描 {target} 端口...\n")
for port in ports:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3)
    result = s.connect_ex((target, port))
    status = "OPEN" if result == 0 else "closed"
    print(f"  {port}: {status}")
    s.close()

print("\n扫描完成")
