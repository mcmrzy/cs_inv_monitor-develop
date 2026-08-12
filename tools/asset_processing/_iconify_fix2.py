# -*- coding: utf-8 -*-
"""修复导航 SVG v2：验证每个配对确实不同
- devices: material-symbols/devices-outline + devices（验证不同）
- ota: mdi/download-outline + mdi/download
- statistics: 还原为 mdi/chart-box-outline + chart-box（MDI 配对正确）
"""
import os
import sys
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")

DIR = r"C:\Users\29538\.qoder\worktree\cs_inv_monitor-develop\dpcN3z\inv_app\assets\icons\csergy"

FIXES = {
    "nav_devices_normal.svg": "material-symbols/devices-outline",
    "nav_devices_active.svg": "material-symbols/devices",
    "nav_ota_normal.svg": "mdi/download-outline",
    "nav_ota_active.svg": "mdi/download",
    "nav_statistics_normal.svg": "mdi/chart-box-outline",
    "nav_statistics_active.svg": "mdi/chart-box",
}


def fetch(icon_id: str) -> str:
    url = f"https://api.iconify.design/{icon_id}.svg?width=24&height=24"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode("utf-8")


contents = {}
for name, icon in FIXES.items():
    try:
        content = fetch(icon)
        if "Not found" in content or len(content) < 100:
            print(f"[MISS] {name} <- {icon} ({len(content)} chars)")
            continue
        contents[name] = content
        dst = os.path.join(DIR, name)
        with open(dst, "w", encoding="utf-8") as fp:
            fp.write(content)
        print(f"[OK] {name} <- {icon} ({len(content)} chars)")
    except Exception as e:
        print(f"[ERR] {name} <- {icon}: {e}")

print()
print("=== 配对差异验证 ===")
for base in ["nav_devices", "nav_ota", "nav_statistics"]:
    n = contents.get(f"{base}_normal.svg")
    a = contents.get(f"{base}_active.svg")
    if n is not None and a is not None:
        print(f"{base}: {'IDENTICAL!' if n == a else 'different'}")
