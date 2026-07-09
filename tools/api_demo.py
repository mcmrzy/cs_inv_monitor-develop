"""
光伏逆变器监控系统 - API Demo
演示：登录鉴权 + 获取设备数据
"""

import requests
import json

# ============ 配置 ============
BASE_URL = "http://192.168.8.50:8888/api/v1"
ACCOUNT = "13800138000"    # 手机号、邮箱或昵称
PASSWORD = "admin123"       # 替换为你的密码

# ============ 工具函数 ============
def print_json(data, title=""):
    """格式化打印 JSON"""
    if title:
        print(f"\n{'='*50}")
        print(f"  {title}")
        print(f"{'='*50}")
    print(json.dumps(data, indent=2, ensure_ascii=False))

# ============ 1. 登录鉴权 ============
print(">>> 步骤1: 登录获取 Token")

login_resp = requests.post(f"{BASE_URL}/auth/login", json={
    "account": ACCOUNT,
    "password": PASSWORD
})

if login_resp.status_code != 200:
    print(f"登录失败: {login_resp.text}")
    exit(1)

login_data = login_resp.json()
if login_data.get("code") != 0:
    print(f"登录失败: {login_data.get('message')}")
    exit(1)

token = login_data["data"]["access_token"]
user_info = login_data["data"].get("user", {})
print(f"✅ 登录成功!")
print(f"   用户: {user_info.get('nickname', 'N/A')} (ID: {user_info.get('id')})")
print(f"   角色: {user_info.get('role')}")
print(f"   Token: {token[:20]}...")

# 设置请求头
headers = {"Authorization": f"Bearer {token}"}

# ============ 2. 获取设备列表 ============
print("\n>>> 步骤2: 获取设备列表")

devices_resp = requests.get(f"{BASE_URL}/devices", headers=headers)
devices_data = devices_resp.json()

if devices_data.get("code") == 0:
    devices = devices_data.get("data", {}).get("items", [])
    total = devices_data.get("data", {}).get("total", 0)
    print(f"✅ 共 {total} 台设备")
    for d in devices[:5]:  # 只显示前5个
        print(f"   - {d.get('sn')} | {d.get('model', 'N/A')} | 状态: {'在线' if d.get('status') == 1 else '离线'}")
else:
    print(f"❌ 获取失败: {devices_data.get('message')}")

# ============ 3. 获取设备实时数据 ============
print("\n>>> 步骤3: 获取设备实时数据")

if devices:
    sn = devices[0].get("sn")
    print(f"查询设备: {sn}")

    realtime_resp = requests.get(f"{BASE_URL}/devices/{sn}/realtime", headers=headers)
    realtime_data = realtime_resp.json()

    if realtime_data.get("code") == 0:
        data = realtime_data.get("data", {})
        print(f"✅ 实时数据:")
        print(f"   有功功率: {data.get('total_active_power', 'N/A')} W")
        print(f"   日发电量: {data.get('daily_energy', 'N/A')} kWh")
        print(f"   内部温度: {data.get('internal_temperature', 'N/A')} ℃")
        print(f"   工作状态: {data.get('work_state_1', 'N/A')}")
    else:
        print(f"❌ 获取失败: {realtime_data.get('message')}")

# ============ 4. 获取电站列表 ============
print("\n>>> 步骤4: 获取电站列表")

stations_resp = requests.get(f"{BASE_URL}/stations", headers=headers)
stations_data = stations_resp.json()

if stations_data.get("code") == 0:
    stations = stations_data.get("data", {}).get("items", [])
    total = stations_data.get("data", {}).get("total", 0)
    print(f"✅ 共 {total} 个电站")
    for s in stations[:3]:
        print(f"   - {s.get('name')} | {s.get('city', 'N/A')} | 容量: {s.get('capacity', 'N/A')} kW")
else:
    print(f"❌ 获取失败: {stations_data.get('message')}")

# ============ 5. 获取告警列表 ============
print("\n>>> 步骤5: 获取告警列表")

alarms_resp = requests.get(f"{BASE_URL}/alarms?page=1&pageSize=5", headers=headers)
alarms_data = alarms_resp.json()

if alarms_data.get("code") == 0:
    alarms = alarms_data.get("data", {}).get("items", [])
    total = alarms_data.get("data", {}).get("total", 0)
    print(f"✅ 共 {total} 条告警")
    for a in alarms[:3]:
        print(f"   - [{a.get('alarm_level')}] {a.get('fault_message', 'N/A')} | 设备: {a.get('device_sn')}")
else:
    print(f"❌ 获取失败: {alarms_data.get('message')}")

# ============ 6. 获取仪表盘统计 ============
print("\n>>> 步骤6: 获取仪表盘统计")

stats_resp = requests.get(f"{BASE_URL}/dashboard/statistics", headers=headers)
stats_data = stats_resp.json()

if stats_data.get("code") == 0:
    stats = stats_data.get("data", {})
    print_json(stats, "仪表盘统计")
else:
    print(f"❌ 获取失败: {stats_data.get('message')}")

print("\n" + "="*50)
print("  Demo 运行完成!")
print("="*50)
