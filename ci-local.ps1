# 本地复现 GitHub Actions go-check job：
#   go build + go vet + go test -race -cover（4 个 Go 模块）
# 用法：pwsh -File ci-local.ps1（在仓库根目录或任意位置）
# 依赖：Go、gcc（MinGW-w64，CGO_ENABLED=1 以支持 -race）
$ErrorActionPreference = 'Continue'
$go = 'C:\Program Files\Go\bin\go.exe'
$env:CGO_ENABLED = '1'
$env:Path = [System.Environment]::GetEnvironmentVariable('Path','User') + ';' + [System.Environment]::GetEnvironmentVariable('Path','Machine')
$root = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path "$root\business-api")) { $root = $PSScriptRoot }
$modules = @('business-api','device-communication','api-gateway','mqtt-kafka-bridge')
$fail = 0
foreach ($m in $modules) {
  Write-Host "===== $m ====="
  Push-Location "$root\$m"
  & $go build ./... 2>&1 | Select-Object -Last 3
  if ($LASTEXITCODE -ne 0) { Write-Host "!! BUILD FAIL: $m"; $fail = 1; Pop-Location; continue }
  & $go vet ./... 2>&1 | Select-Object -Last 3
  if ($LASTEXITCODE -ne 0) { Write-Host "!! VET FAIL: $m"; $fail = 1; Pop-Location; continue }
  & $go test -race -cover '-coverprofile=coverage.out' -count=1 ./... 2>&1 | Select-Object -Last 6
  if ($LASTEXITCODE -ne 0) { Write-Host "!! TEST FAIL: $m"; $fail = 1 } else { Write-Host "OK: $m" }
  Pop-Location
}
Write-Host "===== CI LOCAL RESULT: $fail ====="
exit $fail
