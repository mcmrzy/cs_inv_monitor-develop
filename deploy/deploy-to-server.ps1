# 部署脚本 - 推送服务到服务器
# 服务器: cskj@192.168.8.50

$SERVER = "cskj@192.168.8.50"
$PASSWORD = "REDACTED_ROTATE_CREDENTIAL"
$REMOTE_DIR = "/opt/inv-mqtt"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "光伏逆变器监控系统 - 服务部署" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 检查 sshpass 是否可用
$sshpassAvailable = Get-Command sshpass -ErrorAction SilentlyContinue

if (-not $sshpassAvailable) {
    Write-Host "[提示] sshpass 未安装，将使用交互式密码输入" -ForegroundColor Yellow
    Write-Host ""
}

# 创建远程目录
Write-Host "[1/5] 创建远程目录..." -ForegroundColor Green
if ($sshpassAvailable) {
    sshpass -p $PASSWORD ssh -o StrictHostKeyChecking=no $SERVER "mkdir -p $REMOTE_DIR"
} else {
    Write-Host "请在弹出的终端中输入密码: $PASSWORD" -ForegroundColor Yellow
    ssh -o StrictHostKeyChecking=no $SERVER "mkdir -p $REMOTE_DIR"
}

# 同步代码到服务器
Write-Host "[2/5] 同步代码到服务器..." -ForegroundColor Green
$localPath = "d:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop"
$rsyncPath = "$localPath/*"

if ($sshpassAvailable) {
    sshpass -p $PASSWORD rsync -avz --progress -e "ssh -o StrictHostKeyChecking=no" $rsyncPath ${SERVER}:${REMOTE_DIR}/
} else {
    Write-Host "请在弹出的终端中输入密码: $PASSWORD" -ForegroundColor Yellow
    rsync -avz --progress -e "ssh -o StrictHostKeyChecking=no" $rsyncPath ${SERVER}:${REMOTE_DIR}/
}

# 执行部署
Write-Host "[3/5] 执行部署..." -ForegroundColor Green
$deployCommand = @"
cd $REMOTE_DIR/deploy
docker-compose down
docker-compose up -d --build
"@

if ($sshpassAvailable) {
    sshpass -p $PASSWORD ssh -o StrictHostKeyChecking=no $SERVER $deployCommand
} else {
    Write-Host "请在弹出的终端中输入密码: $PASSWORD" -ForegroundColor Yellow
    ssh -o StrictHostKeyChecking=no $SERVER $deployCommand
}

# 检查服务状态
Write-Host "[4/5] 检查服务状态..." -ForegroundColor Green
if ($sshpassAvailable) {
    sshpass -p $PASSWORD ssh -o StrictHostKeyChecking=no $SERVER "docker ps"
} else {
    Write-Host "请在弹出的终端中输入密码: $PASSWORD" -ForegroundColor Yellow
    ssh -o StrictHostKeyChecking=no $SERVER "docker ps"
}

Write-Host "[5/5] 部署完成!" -ForegroundColor Green
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "部署完成！" -ForegroundColor Green
Write-Host "访问地址: http://192.168.8.50:8888" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
