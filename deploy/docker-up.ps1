[CmdletBinding()]
param(
    [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'
$deployDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $deployDir
$envFile = Join-Path $deployDir '.env.prod'
$composeFile = Join-Path $deployDir 'docker-compose.yml'

if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
    throw "Missing $envFile. Copy deploy/.env.prod.example and fill real secrets first."
}

$content = Get-Content -LiteralPath $envFile -Raw
if ($content -match '(?i)CHANGE_ME|PLACEHOLDER|your_(password|secret|key)') {
    throw "$envFile still contains placeholder secrets."
}
if ($content -notmatch '(?m)^DB_SSL_MODE=require\s*$') {
    throw "DB_SSL_MODE must be require in $envFile."
}

$composeArgs = @('compose', '--env-file', $envFile, '-f', $composeFile, 'up', '-d')
if (-not $NoBuild) {
    $composeArgs += '--build'
}

Push-Location $repoRoot
try {
    & docker @composeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose up failed with exit code $LASTEXITCODE"
    }

    & docker compose --env-file $envFile -f $composeFile ps
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose ps failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
