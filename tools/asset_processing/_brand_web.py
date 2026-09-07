# -*- coding: utf-8 -*-
"""web/Android/iOS 品牌化：CSERGY
- web/index.html: title/description/apple-title/theme-color
- web/manifest.json: name/short_name/colors/description
- AndroidManifest.xml: android:label
- ios Info.plist: CFBundleDisplayName
"""
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

WT = r"C:\Users\29538\.qoder\worktree\cs_inv_monitor-develop\dpcN3z\inv_app"
APP_NAME = "CSERGY 光伏监控"
SHORT = "CSERGY"
DESC = "光伏逆变器智能监控系统"

# ---------- web/index.html ----------
p = os.path.join(WT, "web", "index.html")
t = open(p, encoding="utf-8").read()
t = t.replace('<meta name="description" content="A new Flutter project.">',
              f'<meta name="description" content="{DESC}">')
t = t.replace('<meta name="apple-mobile-web-app-title" content="inv_app">',
              f'<meta name="apple-mobile-web-app-title" content="{SHORT}">')
t = t.replace('<title>inv_app</title>', f'<title>{APP_NAME}</title>')
t = t.replace('<link rel="manifest" href="manifest.json">',
              '<meta name="theme-color" content="#1565C0">\n  <link rel="manifest" href="manifest.json">')
open(p, "w", encoding="utf-8").write(t)
print(f"[OK] web/index.html 品牌化")

# ---------- web/manifest.json ----------
p = os.path.join(WT, "web", "manifest.json")
t = open(p, encoding="utf-8").read()
t = t.replace('"name": "inv_app"', f'"name": "{APP_NAME}"')
t = t.replace('"short_name": "inv_app"', f'"short_name": "{SHORT}"')
t = t.replace('"background_color": "#0175C2"', '"background_color": "#0D47A1"')
t = t.replace('"theme_color": "#0175C2"', '"theme_color": "#1565C0"')
t = t.replace('"description": "A new Flutter project."', f'"description": "{DESC}"')
open(p, "w", encoding="utf-8").write(t)
print(f"[OK] web/manifest.json 品牌化")

# ---------- AndroidManifest.xml ----------
p = os.path.join(WT, "android", "app", "src", "main", "AndroidManifest.xml")
t = open(p, encoding="utf-8").read()
m = re.search(r'android:label="([^"]*)"', t)
if m:
    print(f"  (旧 label: {m.group(1)!r})")
t = re.sub(r'android:label="[^"]*"', f'android:label="{APP_NAME}"', t, count=1)
open(p, "w", encoding="utf-8").write(t)
print(f"[OK] AndroidManifest label -> {APP_NAME}")

# ---------- ios Info.plist ----------
p = os.path.join(WT, "ios", "Runner", "Info.plist")
t = open(p, encoding="utf-8").read()
m = re.search(r'<key>CFBundleDisplayName</key>\s*<string>([^<]*)</string>', t)
if m:
    print(f"  (旧 CFBundleDisplayName: {m.group(1)!r})")
t = re.sub(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)',
           rf'\g<1>{APP_NAME}\g<2>', t, count=1)
open(p, "w", encoding="utf-8").write(t)
print(f"[OK] Info.plist CFBundleDisplayName -> {APP_NAME}")

print("done")
