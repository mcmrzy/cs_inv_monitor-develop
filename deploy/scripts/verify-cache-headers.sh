#!/usr/bin/env bash
# 缓存头校验：打印各路径实际返回的 Cache-Control，与期望值并排对比。
#
# 用法：
#   bash deploy/scripts/verify-cache-headers.sh origin   # 在服务器上执行（--resolve 到 127.0.0.1，绕过 ESA）
#   bash deploy/scripts/verify-cache-headers.sh public   # 任意机器执行（走公网，经阿里云 ESA）
#
# 期望值来源：deploy/CACHE_POLICY.md。ESA 站点缓存模式应为
# 「优先遵循源站缓存策略（如果存在），否则不缓存」。
#
# 注意：ESA 目前会把 Cache-Control 改写为 max-age=30（未遵循源站），
# 因此 public 模式在切换模式前与 origin 结果不一致属于预期现象。
set -u

MODE="${1:-origin}"
APK="${APK:-inv_app_v1.0.1_build10_20260909_1705.apk}"

check() {
  local label="$1" host="$2" path="$3" expect="$4"
  local out http cc
  if [ "$MODE" = "origin" ]; then
    out=$(curl -sk -m 20 -o /dev/null -D - -H "Host: $host" \
      --resolve "$host:443:127.0.0.1" "https://$host$path" 2>/dev/null)
  else
    out=$(curl -s -m 20 -o /dev/null -D - "https://$host$path" 2>/dev/null)
  fi
  http=$(printf '%s\n' "$out" | grep -i '^HTTP' | tail -1 | tr -d '\r')
  cc=$(printf '%s\n' "$out" | grep -i '^cache-control' | tail -1 | tr -d '\r')
  printf '%-20s %-12s %-58s 期望: %s\n' \
    "$label" "${http:-（无响应）}" "${cc:-（无 Cache-Control）}" "$expect"
}

# 从 SPA 首页解析一个真实的构建产物路径（拿不到则退化为 /assets/ 目录）
discover_asset() {
  local host="www.jiuxiaoyw.online" path
  if [ "$MODE" = "origin" ]; then
    path=$(curl -sk -m 20 -H "Host: $host" --resolve "$host:443:127.0.0.1" \
      "https://$host/" 2>/dev/null \
      | grep -oE '/assets/[A-Za-z0-9._-]+\.(js|css)' | head -1)
  else
    path=$(curl -s -m 20 "https://$host/" 2>/dev/null \
      | grep -oE '/assets/[A-Za-z0-9._-]+\.(js|css)' | head -1)
  fi
  printf '%s' "${path:-/assets/}"
}

# speed：连续拉取同一资源，打印缓存命中状态与实际吞吐（切换 ESA 模式后对比用）
if [ "$MODE" = "speed" ]; then
  APK_HOST="${APK_HOST:-www.jiuxiaoyw.online}"
  for i in 1 2 3; do
    hdr=$(mktemp)
    out=$(curl -s -m 120 -o /dev/null -r 0-8000000 -D "$hdr" \
      -w '%{speed_download} %{time_total}' "https://$APK_HOST/firmware/$APK" 2>/dev/null)
    printf '  第 %d 次 8MB: %s KB/s (耗时 %ss) | %s\n' "$i" \
      "$(awk '{printf "%.0f", $1/1024}' <<<"$out")" "$(awk '{print $2}' <<<"$out")" \
      "$(grep -i 'x-site-cache-status' "$hdr" | tail -1 | tr -d '\r')"
    rm -f "$hdr"
    sleep 2
  done
  exit 0
fi

echo "模式: $MODE"

# warm：预热并实测边缘命中（发版后跑一次，让第一个用户也走缓存）
#   APK_HOST 可指定安装包所在域，默认 www.jiuxiaoyw.online
if [ "$MODE" = "warm" ]; then
  APK_HOST="${APK_HOST:-www.jiuxiaoyw.online}"
  warm() {
    local label="$1" url="$2" t
    t=$(curl -s -m 600 -o /dev/null -w '%{time_total}' "$url" 2>/dev/null)
    printf '  预热 %-24s 首次耗时 %ss\n' "$label" "$t"
  }
  warm "SPA 入口 /" "https://www.jiuxiaoyw.online/"
  warm "安装包 ($APK_HOST)" "https://$APK_HOST/firmware/$APK"

  echo "  复验命中状态（连续两次小范围请求）："
  for i in 1 2; do
    out=$(curl -s -m 60 -o /dev/null -D - -r 0-1023 "https://$APK_HOST/firmware/$APK" 2>/dev/null)
    printf '    第 %d 次: %s | %s\n' "$i" \
      "$(printf '%s\n' "$out" | grep -i 'x-site-cache-status' | tail -1 | tr -d '\r')" \
      "$(printf '%s\n' "$out" | grep -i '^age' | tail -1 | tr -d '\r')"
    sleep 3
  done
  exit 0
fi

check "SPA 入口 /"        www.jiuxiaoyw.online      "/"                       "no-cache"
check "构建产物 /assets/" www.jiuxiaoyw.online      "$(discover_asset)"       "immutable 1y"
check "安装包 /firmware/" www.jiuxiaoyw.online      "/firmware/$APK"          "immutable 1y"
check "固件域 /firmware/" download.jiuxiaoyw.online "/firmware/$APK"          "immutable 1y"
check "动态接口 /api/"    api.jiuxiaoyw.online      "/api/v1/ota/app/check?platform=android&version_code=1" "no-store"
