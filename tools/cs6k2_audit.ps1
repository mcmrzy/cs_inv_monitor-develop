[CmdletBinding()]
param(
    [ValidateSet('static', 'unit', 'integration', 'full')]
    [string]$Profile = 'static',

    [string]$OutputDirectory = 'artifacts/cs6k2-audit',

    [switch]$ListOnly,

    [switch]$AllowSkippedIntegration,

    [switch]$InternalOnly
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ManifestPath = Join-Path $RepoRoot 'docs/cs6k2-system-support/test-manifest.json'

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "Missing manifest: $ManifestPath"
}

$Manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $ManifestPath | ConvertFrom-Json
$SelectedGates = @($Manifest.gates | Where-Object { @($_.profiles) -contains $Profile })
if ($InternalOnly) {
    $SelectedGates = @($SelectedGates | Where-Object { $_.kind -eq 'internal' })
}

if ($ListOnly) {
    Write-Host "CS6K2 audit profile: $Profile"
    foreach ($Gate in $SelectedGates) {
        $Requirement = if ($Gate.required) { 'required' } else { 'advisory' }
        if ($Gate.kind -eq 'command') {
            $CommandLine = (@($Gate.command) + @($Gate.args)) -join ' '
            Write-Host ("{0} [{1}] {2} :: {3}" -f $Gate.id, $Requirement, $Gate.title, $CommandLine)
        } else {
            Write-Host ("{0} [{1}] {2} :: internal:{3}" -f $Gate.id, $Requirement, $Gate.title, $Gate.handler)
        }
    }
    exit 0
}

$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$RunDirectory = Join-Path $RepoRoot (Join-Path $OutputDirectory $Timestamp)
New-Item -ItemType Directory -Force -Path $RunDirectory | Out-Null

$Results = New-Object System.Collections.ArrayList

function Add-Result {
    param(
        [object]$Gate,
        [string]$Status,
        [string]$Message,
        [string]$LogPath = ''
    )

    [void]$Results.Add([pscustomobject]@{
        id       = [string]$Gate.id
        title    = [string]$Gate.title
        required = [bool]$Gate.required
        status   = $Status
        message  = $Message
        log      = $LogPath
    })
}

function Invoke-StructureAudit {
    param([object]$Gate)

    $RequiredPaths = @(
        'docs/cs6k2-system-support/README.md',
        'docs/cs6k2-system-support/test-manifest.json',
        'tools/cs6k2_audit.ps1',
        'database/schema.sql',
        'deploy/docker-compose.prod.yml',
        '.github/workflows/ci.yml'
    )

    $Missing = @($RequiredPaths | Where-Object { -not (Test-Path -LiteralPath (Join-Path $RepoRoot $_)) })
    if ($Missing.Count -gt 0) {
        Add-Result $Gate 'failed' ("Missing: " + ($Missing -join ', '))
        return
    }

    $GuideRoot = Join-Path $RepoRoot 'docs/cs6k2-system-support'
    $NumberedGuides = @(Get-ChildItem -LiteralPath $GuideRoot -Filter '*.md' -File | Where-Object { $_.Name -match '^\d{2}-' })
    if ($NumberedGuides.Count -lt 9) {
        Add-Result $Gate 'failed' ("Expected at least 9 numbered guide documents, found {0}." -f $NumberedGuides.Count)
        return
    }

    Add-Result $Gate 'passed' ("Verified {0} required paths and {1} numbered guide documents." -f $RequiredPaths.Count, $NumberedGuides.Count)
}

function Invoke-RepositoryPolicyAudit {
    param([object]$Gate)

    $Problems = New-Object System.Collections.Generic.List[string]
    $PackagePath = Join-Path $RepoRoot 'inv-admin-frontend/package.json'
    $MakefilePath = Join-Path $RepoRoot 'Makefile'
    $CIPath = Join-Path $RepoRoot '.github/workflows/ci.yml'
    $IntegrationRoot = Join-Path $RepoRoot 'tests/integration'

    $Package = Get-Content -Raw -Encoding UTF8 -LiteralPath $PackagePath | ConvertFrom-Json
    $Makefile = Get-Content -Raw -Encoding UTF8 -LiteralPath $MakefilePath
    if (($Makefile -match '(?m)^[^#\r\n]*run\s+lint') -and -not ($Package.scripts.PSObject.Properties.Name -contains 'lint')) {
        $Problems.Add('Makefile invokes npm run lint but package.json has no lint script.')
    }

    $CI = Get-Content -Raw -Encoding UTF8 -LiteralPath $CIPath
    if ($CI -match 'flutter\s+analyze\s*\|\|\s*true') {
        $Problems.Add('CI allows Flutter analyze failures with || true.')
    }
    if (($CI -match 'security-scan:') -and ($CI -match "security-scan:[\s\S]*?if:\s*github\.event_name\s*==\s*'workflow_dispatch'")) {
        $Problems.Add('Security scan is restricted to manual workflow_dispatch.')
    }

    $SkipFiles = @(Get-ChildItem -LiteralPath $IntegrationRoot -Filter '*.go' -File | Where-Object {
        (Get-Content -Raw -Encoding UTF8 -LiteralPath $_.FullName) -match '\bt\.Skip(f|Now)?\s*\('
    } | ForEach-Object { $_.Name })
    if ($SkipFiles.Count -gt 0) {
        $Problems.Add('Mandatory integration sources can skip when services are absent: ' + ($SkipFiles -join ', '))
    }

    if ($Problems.Count -gt 0) {
        Add-Result $Gate 'failed' ($Problems -join ' | ')
        return
    }
    Add-Result $Gate 'passed' 'CI, Makefile and integration skip policy are strict.'
}

function Invoke-SecretScan {
    param([object]$Gate)

    $Git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $Git) {
        Add-Result $Gate 'failed' 'git is required to scan tracked files without exposing values.'
        return
    }

    $Tracked = @(& $Git.Source -C $RepoRoot ls-files)
    if ($LASTEXITCODE -ne 0) {
        Add-Result $Gate 'failed' 'git ls-files failed.'
        return
    }

    $CandidateFiles = @($Tracked | Where-Object {
        ($_ -match '^(deploy|tests/integration)/') -and
        ($_ -match '\.(py|md|go|ya?ml|env|txt)$' -or $_ -match '(^|/)\.env$') -and
        ($_ -notmatch '\.env\.example$')
    })

    $Patterns = @(
        '(?im)^(JWT_SECRET|REDIS_PASSWORD|DB_PASSWORD|MQTT_PASSWORD|EMAIL_PASS|INTERNAL_KEY)\s*=\s*(?!CHANGE_ME|REDACTED|test|example|\$\{|\s*$)[^\s#]{8,}',
        '(?i)client\.connect\([^\r\n]+password\s*=\s*["''][^"'']{6,}["'']',
        '(?i)\b(password|secret|token)\s*=\s*["''][A-Za-z0-9+/=_@.:-]{8,}["'']'
    )

    $Flagged = New-Object System.Collections.Generic.List[string]
    foreach ($RelativePath in $CandidateFiles) {
        $FullPath = Join-Path $RepoRoot $RelativePath
        $Content = Get-Content -Raw -Encoding UTF8 -LiteralPath $FullPath -ErrorAction SilentlyContinue
        foreach ($Pattern in $Patterns) {
            if ($Content -match $Pattern) {
                $Flagged.Add($RelativePath)
                break
            }
        }
    }

    $UniqueFlagged = @($Flagged | Sort-Object -Unique)
    if ($UniqueFlagged.Count -gt 0) {
        Add-Result $Gate 'failed' ("Potential tracked credentials found in {0} file(s); values are intentionally suppressed: {1}" -f $UniqueFlagged.Count, ($UniqueFlagged -join ', '))
        return
    }
    Add-Result $Gate 'passed' ("Scanned {0} tracked deployment/integration files; no high-confidence pattern found." -f $CandidateFiles.Count)
}

function Invoke-MigrationPairAudit {
    param([object]$Gate)

    $MigrationRoot = Join-Path $RepoRoot 'database/migrations'
    $MissingDown = New-Object System.Collections.Generic.List[string]
    foreach ($Up in Get-ChildItem -LiteralPath $MigrationRoot -Filter '*.up.sql' -File) {
        $DownName = $Up.Name -replace '\.up\.sql$', '.down.sql'
        if (-not (Test-Path -LiteralPath (Join-Path $MigrationRoot $DownName))) {
            $MissingDown.Add($Up.Name)
        }
    }

    if ($MissingDown.Count -gt 0) {
        Add-Result $Gate 'warning' ("Missing down/explicit rollback companion for {0} migration(s): {1}" -f $MissingDown.Count, ($MissingDown -join ', '))
        return
    }
    Add-Result $Gate 'passed' 'Every *.up.sql migration has a *.down.sql companion.'
}

function Invoke-InternalGate {
    param([object]$Gate)

    switch ([string]$Gate.handler) {
        'structure'         { Invoke-StructureAudit $Gate }
        'repository_policy' { Invoke-RepositoryPolicyAudit $Gate }
        'secret_scan'       { Invoke-SecretScan $Gate }
        'migration_pairs'   { Invoke-MigrationPairAudit $Gate }
        default             { Add-Result $Gate 'failed' ("Unknown internal handler: " + $Gate.handler) }
    }
}

function Invoke-CommandGate {
    param([object]$Gate)

    $Executable = Get-Command ([string]$Gate.command) -ErrorAction SilentlyContinue
    if ($null -eq $Executable) {
        Add-Result $Gate 'failed' ("Required executable not found: " + $Gate.command)
        return
    }

    $WorkingDirectory = (Resolve-Path (Join-Path $RepoRoot ([string]$Gate.working_directory))).Path
    $LogPath = Join-Path $RunDirectory (([string]$Gate.id) + '.log')
    $Arguments = @($Gate.args | ForEach-Object { [string]$_ })

    Write-Host ("Running {0}: {1}" -f $Gate.id, $Gate.title)
    Push-Location $WorkingDirectory
    try {
        $Output = @(& $Executable.Source @Arguments 2>&1)
        $ExitCode = $LASTEXITCODE
        $Output | Set-Content -Encoding UTF8 -LiteralPath $LogPath
    } finally {
        Pop-Location
    }

    $RelativeLog = $LogPath.Substring($RepoRoot.Length).TrimStart('\', '/')
    if ($ExitCode -ne 0) {
        Add-Result $Gate 'failed' ("Exit code: $ExitCode") $RelativeLog
        return
    }

    $SkipFound = $false
    if ($Gate.PSObject.Properties.Name -contains 'fail_on_skip' -and [bool]$Gate.fail_on_skip) {
        $SkipFound = ($Output -join "`n") -match '(?m)^--- SKIP:'
    }
    if ($SkipFound -and -not $AllowSkippedIntegration) {
        Add-Result $Gate 'failed' 'Mandatory integration test output contains SKIP. Start the full test stack or fix the test precondition.' $RelativeLog
        return
    }
    if ($SkipFound) {
        Add-Result $Gate 'warning' 'Integration output contains SKIP and was allowed only for local inventory; not valid release evidence.' $RelativeLog
        return
    }

    Add-Result $Gate 'passed' 'Command completed successfully.' $RelativeLog
}

foreach ($Gate in $SelectedGates) {
    if ($Gate.kind -eq 'internal') {
        Invoke-InternalGate $Gate
    } else {
        Invoke-CommandGate $Gate
    }
}

$RequiredFailures = @($Results | Where-Object { $_.required -and $_.status -eq 'failed' })
$Warnings = @($Results | Where-Object { $_.status -eq 'warning' })
$Summary = [pscustomobject]@{
    product          = $Manifest.product
    profile          = $Profile
    started_at_local = $Timestamp
    passed           = @($Results | Where-Object { $_.status -eq 'passed' }).Count
    failed_required  = $RequiredFailures.Count
    warnings         = $Warnings.Count
    release_evidence = ($RequiredFailures.Count -eq 0 -and $Warnings.Count -eq 0 -and -not $AllowSkippedIntegration)
    results          = $Results
}

$SummaryPath = Join-Path $RunDirectory 'summary.json'
$Summary | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $SummaryPath

Write-Host ''
Write-Host ("CS6K2 audit complete: passed={0}, required failures={1}, warnings={2}" -f $Summary.passed, $Summary.failed_required, $Summary.warnings)
Write-Host ("Summary: {0}" -f $SummaryPath)

foreach ($Result in $Results) {
    Write-Host ("{0,-9} {1} - {2}" -f $Result.status.ToUpperInvariant(), $Result.id, $Result.message)
}

if ($RequiredFailures.Count -gt 0) {
    exit 1
}
exit 0
