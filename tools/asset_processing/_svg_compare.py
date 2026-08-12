# -*- coding: utf-8 -*-
"""对比 active/normal SVG 是否真正不同"""
import os
import sys

sys.stdout.reconfigure(encoding="utf-8")

DIR = r"C:\Users\29538\.qoder\worktree\cs_inv_monitor-develop\dpcN3z\inv_app\assets\icons\csergy"
pairs = [
    ("nav_statistics_normal.svg", "nav_statistics_active.svg"),
    ("nav_ota_normal.svg", "nav_ota_active.svg"),
    ("nav_devices_normal.svg", "nav_devices_active.svg"),
    ("nav_home_normal.svg", "nav_home_active.svg"),
    ("nav_alarms_normal.svg", "nav_alarms_active.svg"),
    ("nav_profile_normal.svg", "nav_profile_active.svg"),
]
for a, b in pairs:
    pa = os.path.join(DIR, a)
    pb = os.path.join(DIR, b)
    if not (os.path.exists(pa) and os.path.exists(pb)):
        print(f"{a} vs {b}: [SKIP] 文件缺失（已删除则属正常）")
        continue
    ca = open(pa, encoding="utf-8").read()
    cb = open(pb, encoding="utf-8").read()
    same = ca == cb
    status = "IDENTICAL!" if same else "different"
    print(f"{a} vs {b}: {status}")
    if same:
        print("   content:", ca[:180])
    else:
        # 提取 path d 属性对比
        import re
        da = re.search(r'd="([^"]*)"', ca)
        db = re.search(r'd="([^"]*)"', cb)
        print("  normal d:", da.group(1)[:100] if da else "N/A")
        print("  active d:", db.group(1)[:100] if db else "N/A")
