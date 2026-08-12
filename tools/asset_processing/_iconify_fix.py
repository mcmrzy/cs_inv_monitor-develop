# -*- coding: utf-8 -*-
"""修复导航 SVG：active/normal 配对 + Material Symbols 统一风格
- nav_devices: devices-outline (normal) / devices (active) —— MDI 无 outline 版，用 MS 补齐
- nav_ota: download-outline (normal) / download (active)
- 其余保持 MDI（已有正确 outline/fill 配对）
"""
import os
import sys
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")

DIR = r"C:\Users\29538\.qoder\worktree\cs_inv_monitor-develop\dpcN3z\inv_app\assets\icons\csergy"

# 需要修复的映射
FIXES = {
    "nav_devices_normal.svg": "material-symbols/devices-outline",
    "nav_devices_active.svg": "material-symbols/devices",
    "nav_ota_normal.svg": "material-symbols/download-outline",
    "nav_ota_active.svg": "material-symbols/download",
    # 顺带统一 statistics 为 MS monitoring 系列（保持 outline/fill 配对语义一致）
    "nav_statistics_normal.svg": "material-symbols/monitoring-outline",
    "nav_statistics_active.svg": "material-symbols/monitoring",
    # home/alarms/profile 保持现有 MDI 配对，不重复下载
}


def fetch(icon_id: str) -> str:
    url = f"https://api.iconify.design/{icon_id}.svg?width=24&height=24"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode("utf-8")


for name, icon in FIXES.items():
    try:
        content = fetch(icon)
        if "Not found" in content or len(content) < 100:
            print(f"[MISS] {name} <- {icon} ({len(content)} chars)")
            continue
        dst = os.path.join(DIR, name)
        with open(dst, "w", encoding="utf-8") as fp:
            fp.write(content)
        print(f"[OK] {name} <- {icon} ({len(content)} chars)")
    except Exception as e:
        print(f"[ERR] {name} <- {icon}: {e}")
