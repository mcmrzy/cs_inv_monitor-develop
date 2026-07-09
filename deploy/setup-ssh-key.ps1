# SSH 密钥部署脚本
# 将公钥上传到服务器，实现免密码登录

$SERVER = "cskj@192.168.8.50"
$PASSWORD = "cskj9527"
$PUB_KEY = Get-Content "$env:USERPROFILE\.ssh\id_rsa_deploy.pub"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SSH 密钥部署" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 创建远程目录和添加公钥
$sshCommand = @"
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo '$PUB_KEY' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
echo 'SSH公钥已添加'
"@

Write-Host "正在将公钥上传到服务器..." -ForegroundColor Green
Write-Host "请在弹出的终端中输入密码: $PASSWORD" -ForegroundColor Yellow

# 使用 ssh 执行命令
ssh -o StrictHostKeyChecking=no $SERVER $sshCommand

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SSH 密钥部署完成！" -ForegroundColor Green
Write-Host "现在可以免密码登录服务器了" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
