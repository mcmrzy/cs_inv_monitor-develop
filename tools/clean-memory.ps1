#Requires -Version 5.1
<#
.SYNOPSIS
    Windows Memory Cleanup Tool v1.0
.DESCRIPTION
    Clean file system cache and process working set memory, stop Gradle daemons, show top memory consumers.
.PARAMETER WhatIf
    Dry run - show what would be done without actually cleaning.
.PARAMETER TopN
    Number of top memory processes to display, default 15.
.PARAMETER SkipGradle
    Skip Gradle daemon cleanup.
.PARAMETER SkipKill
    Skip interactive high-memory process termination.
.EXAMPLE
    .\clean-memory.ps1
    .\clean-memory.ps1 -WhatIf
    .\clean-memory.ps1 -TopN 20 -SkipGradle
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [int]$TopN = 15,
    [switch]$SkipGradle,
    [switch]$SkipKill
)

# -- P/Invoke: EmptyWorkingSet ------------------------------------------------
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class MemHelper {
    [DllImport("psapi.dll", SetLastError = true)]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetCurrentProcess();
}
"@ -ErrorAction SilentlyContinue

# -- Helper Functions ---------------------------------------------------------

function Get-MemoryInfo {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $freeGB  = [math]::Round($os.FreePhysicalMemory     / 1MB, 1)
    $usedGB  = [math]::Round($totalGB - $freeGB, 1)
    $pct     = [math]::Round(($usedGB / $totalGB) * 100, 1)
    [PSCustomObject]@{
        TotalGB = $totalGB
        UsedGB  = $usedGB
        FreeGB  = $freeGB
        Percent = $pct
    }
}

function Show-MemoryStatus {
    param([string]$Label, [object]$Info)

    Write-Host ""
    Write-Host "  $Label" -ForegroundColor Cyan

    # Progress bar (24 chars using # and .)
    $barLen = 24
    $filled = [math]::Round($Info.Percent / 100 * $barLen)
    $empty  = $barLen - $filled
    $bar    = ("#" * $filled) + ("." * $empty)

    # Status label + color
    if ($Info.Percent -ge 90) {
        $status = "  [!!] DANGER"
        $color  = 'Red'
    } elseif ($Info.Percent -ge 75) {
        $status = "  [!] HIGH"
        $color  = 'Yellow'
    } else {
        $status = "  [OK] Normal"
        $color  = 'Green'
    }

    Write-Host "    Total:    $($Info.TotalGB) GB"
    Write-Host -NoNewline "    Used:     $($Info.UsedGB) GB  [$bar]"
    Write-Host -NoNewline "  $($Info.Percent)%" -ForegroundColor $color
    Write-Host $status -ForegroundColor $color
    Write-Host "    Free:     $($Info.FreeGB) GB"
}

function Show-TopProcesses {
    param([int]$N)

    Write-Host ""
    Write-Host "  [TOP] Memory usage Top $N processes:" -ForegroundColor Cyan
    Write-Host "    #    Process Name                 PID       Mem(MB)" -ForegroundColor DarkGray
    Write-Host "    $('=' * 55)" -ForegroundColor DarkGray

    $procs = Get-Process |
        Where-Object { $_.WorkingSet64 -gt 0 } |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First $N

    $i = 0
    foreach ($p in $procs) {
        $i++
        $mb = [math]::Round($p.WorkingSet64 / 1MB, 0)
        $name = if ($p.ProcessName.Length -gt 28) { $p.ProcessName.Substring(0, 28) } else { $p.ProcessName }
        $line = "    {0,-4} {1,-28} {2,-9} {3,8}" -f $i, $name, $p.Id, $mb
        if ($mb -ge 1024) {
            Write-Host $line -ForegroundColor Red
        } elseif ($mb -ge 512) {
            Write-Host $line -ForegroundColor Yellow
        } else {
            Write-Host $line
        }
    }
    $procs
}

function Invoke-MemoryCleanup {
    param([bool]$DryRun)

    Write-Host ""
    Write-Host "  [CLEAN] Cleaning process working sets..." -ForegroundColor Cyan

    $totalFreed = 0
    $cleaned    = 0
    $skipped    = 0

    $procs = Get-Process |
        Where-Object { $_.WorkingSet64 -gt 10MB } |
        Sort-Object WorkingSet64 -Descending

    foreach ($p in $procs) {
        $before = $p.WorkingSet64
        $name   = $p.ProcessName
        $pid    = $p.Id

        if ($DryRun) {
            $mb = [math]::Round($before / 1MB, 0)
            Write-Host "    [WhatIf] Would clean $name ($pid): ~$mb MB" -ForegroundColor DarkYellow
            continue
        }

        try {
            $ok = [MemHelper]::EmptyWorkingSet($p.Handle)
            if ($ok) {
                $p.Refresh()
                $freed = $before - $p.WorkingSet64
                if ($freed -gt 0) {
                    $freedMB = [math]::Round($freed / 1MB, 0)
                    $totalFreed += $freed
                    $cleaned++
                    Write-Host "    [OK] Freed $name ($pid): $freedMB MB" -ForegroundColor Green
                }
            } else {
                $skipped++
            }
        } catch {
            $skipped++
            # Insufficient privileges or process exited - skip silently
        }
    }

    if (-not $DryRun) {
        $freedGB = [math]::Round($totalFreed / 1GB, 2)
        Write-Host ""
        Write-Host "    Cleaned: $cleaned | Skipped: $skipped | Freed: $freedGB GB" -ForegroundColor White
    }
    $totalFreed
}

function Stop-GradleDaemons {
    param([bool]$DryRun)

    Write-Host ""
    Write-Host "  [GRADLE] Cleaning Gradle daemons..." -ForegroundColor Cyan

    $gradleProcs = Get-Process -Name "java" -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $_.CommandLine -match "GradleDaemon|gradle" -or
                $_.Modules.FileName -match "gradle"
            } catch {
                $false
            }
        }

    if (-not $gradleProcs) {
        $gradleProcs = Get-Process -Name "java" -ErrorAction SilentlyContinue |
            Where-Object {
                try { $_.Path -match "gradle" } catch { $false }
            }
    }

    if (-not $gradleProcs) {
        Write-Host "    No Gradle daemon process found" -ForegroundColor DarkGray

        # Try gradlew --stop if available
        $gradlew = Get-ChildItem -Path $PSScriptRoot, "$PSScriptRoot\.." -Filter "gradlew.bat" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($gradlew) {
            if ($DryRun) {
                Write-Host "    [WhatIf] Would run: $($gradlew.FullName) --stop" -ForegroundColor DarkYellow
            } else {
                Write-Host "    Running gradlew --stop ..." -ForegroundColor DarkGray
                try {
                    & $gradlew.FullName --stop 2>$null | Out-Null
                    Write-Host "    [OK] gradlew --stop executed" -ForegroundColor Green
                } catch {
                    Write-Host "    gradlew --stop failed (can be ignored)" -ForegroundColor DarkGray
                }
            }
        }
        return
    }

    foreach ($gp in $gradleProcs) {
        $mb = [math]::Round($gp.WorkingSet64 / 1MB, 0)
        if ($DryRun) {
            Write-Host "    [WhatIf] Would kill Gradle process $($gp.Id) ($mb MB)" -ForegroundColor DarkYellow
        } else {
            try {
                Stop-Process -Id $gp.Id -Force
                Write-Host "    [OK] Killed Gradle daemon ($($gp.Id)): $mb MB" -ForegroundColor Green
            } catch {
                Write-Host "    [X] Cannot kill $($gp.Id): $_" -ForegroundColor Red
            }
        }
    }
}

function Invoke-KillHighMemory {
    param([bool]$DryRun)

    if ($DryRun) { return }

    Write-Host ""
    Write-Host "  [KILL] High memory process handling" -ForegroundColor Yellow
    Write-Host "    Enter number to kill a process (press Enter to skip)" -ForegroundColor DarkGray

    $procs = Get-Process |
        Where-Object { $_.WorkingSet64 -gt 256MB } |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First 10

    $i = 0
    $list = @()
    foreach ($p in $procs) {
        $i++
        $mb = [math]::Round($p.WorkingSet64 / 1MB, 0)
        $list += $p
        Write-Host "    [$i] $($p.ProcessName) (PID $($p.Id)) - $mb MB" -ForegroundColor Yellow
    }

    if ($list.Count -eq 0) {
        Write-Host "    No high-memory processes to handle" -ForegroundColor DarkGray
        return
    }

    while ($true) {
        $input_str = Read-Host "    Enter number to kill (or Enter to skip)"
        if ([string]::IsNullOrWhiteSpace($input_str)) { break }
        if ($input_str -match '^\d+$') {
            $idx = [int]$input_str - 1
            if ($idx -ge 0 -and $idx -lt $list.Count) {
                $target = $list[$idx]
                $confirm = Read-Host "    Confirm kill $($target.ProcessName) (PID $($target.Id))? (y/N)"
                if ($confirm -eq 'y' -or $confirm -eq 'Y') {
                    try {
                        Stop-Process -Id $target.Id -Force
                        Write-Host "    [OK] Killed $($target.ProcessName) ($($target.Id))" -ForegroundColor Green
                    } catch {
                        Write-Host "    [X] Cannot kill: $_" -ForegroundColor Red
                    }
                }
            } else {
                Write-Host "    Index out of range" -ForegroundColor Red
            }
        } else {
            Write-Host "    Please enter a numeric index" -ForegroundColor Red
        }
    }
}

# -- Main Flow ----------------------------------------------------------------

$line = "=" * 50
Write-Host ""
Write-Host $line -ForegroundColor Magenta
Write-Host "  Memory Cleanup Tool v1.0" -ForegroundColor Magenta
Write-Host $line -ForegroundColor Magenta

$dryRun = $WhatIfPreference -or $PSBoundParameters.ContainsKey('WhatIf')
if ($dryRun) {
    Write-Host "  [WhatIf Mode] Display only, no actual cleanup" -ForegroundColor DarkYellow
}

# 1) Memory status before cleanup
$before = Get-MemoryInfo
Show-MemoryStatus -Label "[STAT] Current memory status:" -Info $before

# 2) Top N processes
$topProcs = Show-TopProcesses -N $TopN

# 3) Clean Gradle daemon
if (-not $SkipGradle) {
    Stop-GradleDaemons -DryRun $dryRun
}

# 4) Clean process working sets
Invoke-MemoryCleanup -DryRun $dryRun | Out-Null

# 5) Interactive kill high-memory processes
if (-not $SkipKill -and -not $dryRun) {
    Invoke-KillHighMemory -DryRun $dryRun
}

# 6) Memory status after cleanup
if (-not $dryRun) {
    Start-Sleep -Seconds 2
    $after = Get-MemoryInfo
    Show-MemoryStatus -Label "[STAT] Memory status after cleanup:" -Info $after

    $freedGB = [math]::Round($before.UsedGB - $after.UsedGB, 1)
    if ($freedGB -gt 0) {
        Write-Host ""
        Write-Host "    ** Freed approximately $freedGB GB of memory! **" -ForegroundColor Green
    } elseif ($freedGB -eq 0) {
        Write-Host ""
        Write-Host "    No significant change in memory usage" -ForegroundColor DarkGray
    } else {
        Write-Host ""
        Write-Host "    Memory usage slightly increased (normal system activity)" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host $line -ForegroundColor Magenta
Write-Host ""
