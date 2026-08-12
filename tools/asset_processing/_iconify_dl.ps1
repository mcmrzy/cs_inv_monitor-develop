# 用 Iconify API 批量下载专业矢量图标，重做全部 24 个 SVG
$ErrorActionPreference = "Stop"
$dir = "C:\Users\29538\.qoder\worktree\cs_inv_monitor-develop\dpcN3z\inv_app\assets\icons\csergy"
# 映射表: 文件名 -> Iconify 集/图标名
$map = @{
  # 导航（Material Design Icons，保持现有视觉风格）
  "nav_home_normal.svg"      = "mdi/home-outline"
  "nav_home_active.svg"      = "mdi/home"
  "nav_statistics_normal.svg" = "mdi/chart-box-outline"
  "nav_statistics_active.svg" = "mdi/chart-box"
  "nav_devices_normal.svg"   = "mdi/devices"
  "nav_devices_active.svg"   = "mdi/devices"
  "nav_alarms_normal.svg"    = "mdi/bell-outline"
  "nav_alarms_active.svg"    = "mdi/bell"
  "nav_profile_normal.svg"   = "mdi/account-outline"
  "nav_profile_active.svg"   = "mdi/account"
  # 功能图标（Lucide 统一线性风格）
  "battery.svg"        = "lucide/battery-charging"
  "energy_flow.svg"    = "lucide/activity"
  "firmware.svg"       = "lucide/circuit-board"
  "grid.svg"           = "lucide/grid-3x3"
  "inverter.svg"       = "lucide/plug-zap"
  "load.svg"           = "lucide/gauge"
  "monitoring.svg"     = "lucide/line-chart"
  "power.svg"          = "lucide/power"
  "solar.svg"          = "lucide/sun"
  "storage.svg"        = "lucide/database"
  "warning.svg"        = "lucide/triangle-alert"
  "wifi.svg"           = "lucide/wifi"
  "nav_ota_normal.svg" = "lucide/download"
  "nav_ota_active.svg" = "lucide/download"
}
foreach ($k in $map.Keys) {
  $icon = $map[$k]
  $url = "https://api.iconify.design/$icon.svg?width=24&height=24"
  $dst = Join-Path $dir $k
  curl -s -L -m 30 -o $dst $url
  if (Test-Path $dst) {
    $sz = (Get-Item $dst).Length
    if ($sz -lt 100) { Write-Output "FAIL($sz) $k <- $icon" }
    else { Write-Output "OK $k <- $icon ($sz bytes)" }
  } else {
    Write-Output "FAIL $k <- $icon"
  }
  Start-Sleep -Milliseconds 200
}
