# -*- coding: utf-8 -*-
"""Android 12+（含 Android 14）系统 SplashScreen 修复：
1. values-v31: 背景改为开屏图顶部主色 #6EABE4，图标改为应用图标（不再透明纯蓝屏）
2. values/values-night NormalTheme 窗口背景同步为主色，消除首帧间隙闪白/闪黑
3. 删除不再引用的 splash_gradient.xml / splash_icon_transparent.xml
"""
import os
import sys

sys.stdout.reconfigure(encoding="utf-8")

RES = r"C:\Users\29538\.qoder\worktree\cs_inv_monitor-develop\dpcN3z\inv_app\android\app\src\main\res"

# ===== 1. values-v31/styles.xml =====
p31 = os.path.join(RES, "values-v31", "styles.xml")
t = open(p31, encoding="utf-8").read()
old = """        <item name="android:windowSplashScreenBackground">@drawable/splash_gradient</item>
        <item name="android:windowSplashScreenAnimatedIcon">@drawable/splash_icon_transparent</item>
        <item name="android:windowSplashScreenIconBackgroundColor">@android:color/transparent</item>"""
new = """        <!-- 背景取开屏图顶部主色（#6EABE4 浅蓝），图标用应用图标；
             Android 12+ 平台强制系统启动屏，无法全屏图，同色衔接 Flutter 开屏页 -->
        <item name="android:windowSplashScreenBackground">#6EABE4</item>
        <item name="android:windowSplashScreenAnimatedIcon">@mipmap/ic_launcher</item>
        <item name="android:windowSplashScreenIconBackgroundColor">@android:color/transparent</item>"""
assert old in t, "values-v31: 未找到目标 item 块"
t = t.replace(old, new)
open(p31, "w", encoding="utf-8").write(t)
print("[OK] values-v31/styles.xml")

# ===== 2. values/styles.xml + values-night/styles.xml: NormalTheme 窗口背景 =====
for rel in ["values", "values-night"]:
    p = os.path.join(RES, rel, "styles.xml")
    t = open(p, encoding="utf-8").read()
    old_bg = '<item name="android:windowBackground">?android:colorBackground</item>'
    new_bg = (
        "<!-- 与开屏图顶部主色一致：系统启动屏退出到 Flutter 首帧的间隙不闪白/黑 -->\n"
        '        <item name="android:windowBackground">#6EABE4</item>'
    )
    assert old_bg in t, f"{rel}: 未找到 NormalTheme 背景行"
    t = t.replace(old_bg, new_bg)
    open(p, "w", encoding="utf-8").write(t)
    print(f"[OK] {rel}/styles.xml")

# ===== 3. 删除不再引用的 drawable =====
for f in ["splash_gradient.xml", "splash_icon_transparent.xml"]:
    p = os.path.join(RES, "drawable", f)
    if os.path.exists(p):
        os.remove(p)
        print(f"[OK] 删除 drawable/{f}")
    else:
        print(f"[SKIP] drawable/{f} 不存在")

print("done")
