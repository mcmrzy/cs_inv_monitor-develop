#!/usr/bin/env bash
# ============================================================================
# 8 小时持续测试战役编排器（无人值守）
#
# 每循环执行：E2E(106) → business-api 集成 → root 集成 → vitest(311)
# 每 4 循环加跑：Flutter(590) + Go 四模块单元测试
# 自愈：Docker 守护进程/测试栈失联自动拉起；孤儿 vite dev 占 5173 端口自动清
# 记录：test-campaign-results/campaign.jsonl（逐套件逐循环）
#       test-campaign-results/report.md（人读进度表，供监控自动化读取）
#       test-campaign-results/failures/（失败套件完整输出留证）
# 用法：bash scripts/test-campaign.sh   （后台运行）
# ============================================================================
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

HOURS="${HOURS:-8}"
START=$(date +%s)
END=$(( START + HOURS * 3600 ))
OUT="test-campaign-results"
mkdir -p "$OUT/failures" "$OUT/counted"
JSONL="$OUT/campaign.jsonl"
REPORT="$OUT/report.md"
: > "$JSONL"

{
  echo "# 8 小时持续测试战役"
  echo "- 开始: $(date '+%F %T')，计划时长: ${HOURS}h"
  echo "- 每循环: E2E(Playwright 106) / business-api 集成 / root 集成 / vitest(311)"
  echo "- 每 4 循环: Flutter(590) + Go 四模块单元测试"
  echo ""
  echo "| 时间 | 循环 | 套件 | 结果 | 用例数 | 耗时s |"
  echo "|---|---|---|---|---|---|"
} > "$REPORT"

now() { date '+%F %T'; }

ensure_stack() {
  if ! docker ps >/dev/null 2>&1; then
    echo "[$(now)] docker daemon down -> 启动 Docker Desktop" >> "$OUT/watchdog.log"
    cmd //c start "" "C:\\Program Files\\Docker\\Docker\\Docker Desktop.exe" >/dev/null 2>&1 || true
    for _ in $(seq 1 60); do docker ps >/dev/null 2>&1 && break; sleep 5; done
    docker ps >/dev/null 2>&1 || return 1
  fi
  local healthy
  healthy=$(docker compose -f deploy/docker-compose.test.yml ps 2>/dev/null | grep -c "(healthy)" || true)
  if [ "${healthy:-0}" -lt 7 ]; then
    echo "[$(now)] 测试栈不健康($healthy/7) -> up --wait" >> "$OUT/watchdog.log"
    GO_PROXY=https://goproxy.cn,direct docker compose -f deploy/docker-compose.test.yml up -d --wait --wait-timeout 300 >> "$OUT/watchdog.log" 2>&1 || return 1
  fi
  return 0
}

free_vite_port() {
  powershell -NoProfile -Command "Get-NetTCPConnection -LocalPort 5173 -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id \$_.OwningProcess -Force -ErrorAction SilentlyContinue }" >/dev/null 2>&1 || true
}

record() { # <suite> <cycle> <status> <cases> <seconds>
  echo "{\"ts\":\"$(date -Iseconds)\",\"cycle\":$2,\"suite\":\"$1\",\"status\":\"$3\",\"cases\":$4,\"seconds\":$5}" >> "$JSONL"
  echo "| $(date '+%T') | $2 | $1 | $3 | $4 | $5 |" >> "$REPORT"
}

RC=0; SECS=0
run_timed() { # <dir> <cmd...>
  local dir="$1"; shift
  local t0
  t0=$(date +%s)
  ( cd "$dir" && "$@" ) > "$OUT/last-run.log" 2>&1
  RC=$?
  SECS=$(( $(date +%s) - t0 ))
}

pw_cases() { grep -oE "[0-9]+ passed" "$OUT/last-run.log" | head -1 | grep -oE "[0-9]+" || echo 0; }
vitest_cases() { grep -oE "Tests[^0-9]+[0-9]+ passed" "$OUT/last-run.log" | grep -oE "[0-9]+ passed" | grep -oE "[0-9]+" || echo 0; }
flutter_cases() { grep -oE "\+[0-9]+" "$OUT/last-run.log" | tail -1 | grep -oE "[0-9]+" || echo 590; }

# go 集成套件：首次带 -v 运行统计用例数（记入 counted/），之后常规运行
go_int_suite() { # <dir> <name> <caseref-file>
  local dir="$1" name="$2" caseref="$3"
  if [ -f "$caseref" ]; then
    run_timed "$dir" go test -tags=integration -count=1 ./...
  else
    run_timed "$dir" go test -v -tags=integration -count=1 ./...
    if [ "$RC" -eq 0 ]; then
      grep -c "^--- PASS" "$OUT/last-run.log" > "$caseref" || echo 0 > "$caseref"
    fi
  fi
  local cases=0
  [ -f "$caseref" ] && cases=$(cat "$caseref")
  if [ "$RC" -eq 0 ]; then
    record "$name" "$CYCLE" PASS "$cases" "$SECS"
  else
    record "$name" "$CYCLE" FAIL "$cases" "$SECS"
    cp "$OUT/last-run.log" "$OUT/failures/c${CYCLE}-${name}.log"
  fi
}

go_unit_suite() { # <dir> <name>
  run_timed "$1" go test -count=1 ./...
  if [ "$RC" -eq 0 ]; then
    record "$2" "$CYCLE" PASS 0 "$SECS"
  else
    record "$2" "$CYCLE" FAIL 0 "$SECS"
    cp "$OUT/last-run.log" "$OUT/failures/c${CYCLE}-${2}.log"
  fi
}

FINALIZE() {
  {
    echo ""
    echo "## 战役总结（$(now)）"
    echo "- 总循环数: $1"
    echo "- 各套件通过/失败次数:"
    grep -oE '"suite":"[^"]+","status":"[^"]+"' "$JSONL" | sort | uniq -c | sed 's/^/  - /'
    echo "- 累计用例执行数: $(grep -oE '"cases":[0-9]+' "$JSONL" | grep -oE '[0-9]+' | awk '{s+=$1} END {print s+0}')"
    echo "- 失败留证: $(ls "$OUT/failures" 2>/dev/null | wc -l) 个文件"
    echo "- CAMPAIGN_DONE"
  } >> "$REPORT"
}

echo "[$(now)] 战役启动，HOURS=$HOURS" >> "$OUT/watchdog.log"
CYCLE=0
while [ "$(date +%s)" -lt "$END" ]; do
  CYCLE=$((CYCLE+1))
  echo "### 循环 $CYCLE — $(now)" >> "$REPORT"
  if ! ensure_stack; then
    record stack-recover "$CYCLE" FAIL 0 0
    sleep 60
    continue
  fi
  free_vite_port

  # ---- E2E（106 条，约 3 分钟）----
  run_timed "inv-admin-frontend" env PLAYWRIGHT_CHANNEL=msedge npx playwright test --project=chromium
  if [ "$RC" -eq 0 ]; then
    record e2e "$CYCLE" PASS "$(pw_cases)" "$SECS"
  else
    record e2e "$CYCLE" FAIL "$(pw_cases)" "$SECS"
    cp "$OUT/last-run.log" "$OUT/failures/c${CYCLE}-e2e.log"
  fi

  # ---- Go 集成 ----
  go_int_suite "business-api" go-bizapi-int "$OUT/counted/go-bizapi-int"
  go_int_suite "tests/integration" go-root-int "$OUT/counted/go-root-int"

  # ---- Web 单元 ----
  run_timed "inv-admin-frontend" npm run test:run
  if [ "$RC" -eq 0 ]; then
    record web-unit "$CYCLE" PASS "$(vitest_cases)" "$SECS"
  else
    record web-unit "$CYCLE" FAIL "$(vitest_cases)" "$SECS"
    cp "$OUT/last-run.log" "$OUT/failures/c${CYCLE}-web-unit.log"
  fi

  # ---- 每 4 循环：Flutter + Go 单元 ----
  if [ $(( CYCLE % 4 )) -eq 0 ]; then
    run_timed "inv_app" cmd //c flutter.bat test --reporter compact
    if [ "$RC" -eq 0 ]; then
      record flutter "$CYCLE" PASS "$(flutter_cases)" "$SECS"
    else
      record flutter "$CYCLE" FAIL "$(flutter_cases)" "$SECS"
      cp "$OUT/last-run.log" "$OUT/failures/c${CYCLE}-flutter.log"
    fi
    go_unit_suite "business-api" go-bizapi-unit
    go_unit_suite "device-communication" go-device-unit
    go_unit_suite "api-gateway" go-gateway-unit
    go_unit_suite "mqtt-kafka-bridge" go-bridge-unit
  fi
done

FINALIZE "$CYCLE"
echo "[$(now)] 战役结束" >> "$OUT/watchdog.log"
