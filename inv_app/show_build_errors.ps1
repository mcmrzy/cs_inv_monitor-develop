param(
    [Parameter(Mandatory = $true)]
    [string]$LogPath
)

if (-not (Test-Path -LiteralPath $LogPath)) {
    Write-Host "日志不存在: $LogPath"
    exit 0
}

Write-Host ""
Write-Host "============================================================"
Write-Host "  关键错误摘要"
Write-Host "============================================================"

$pattern = 'error:|Error:|FAILURE:|Unresolved reference|Could not |Execution failed|Caused by:|Target of URI doesn''t exist|Failed to |Exception|error -'
$hits = Select-String -LiteralPath $LogPath -Pattern $pattern -CaseSensitive:$false -ErrorAction SilentlyContinue
if ($hits) {
    $hits | Select-Object -First 80 | ForEach-Object { $_.Line }
} else {
    Write-Host "(未匹配到常见错误关键字，展示日志末尾)"
}

Write-Host ""
Write-Host "-------- 日志最后 80 行 --------"
Get-Content -LiteralPath $LogPath -Tail 80
Write-Host "--------------------------------"
Write-Host "完整日志: $((Resolve-Path -LiteralPath $LogPath).Path)"
