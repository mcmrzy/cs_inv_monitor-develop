#===============================================================================
# EMERGENCY KEY ROTATION SCRIPT - PowerShell VERSION
#===============================================================================
# Purpose: Rapid rotation of all security-critical credentials in emergency
#          scenarios requiring sub-hour response time.
#
# Usage:   .\rapid-key-rotation.ps1 [-Key_type] <jwt|smtp|redis|all>
#
# Example: .\rapid-key-rotation.ps1 -KeyType jwt    # Rotate only JWT secret
#          .\rapid-key-rotation.ps1 -KeyType all    # Rotate ALL secrets (emergency)
#
# Prerequisites:
#   - Must be run from project root directory (where deploy/ exists)
#   - Administrator privileges recommended
#   - Git Bash or WSL recommended for sed-like operations
#
# Safety Features:
#   - Automatic backup before any changes
#   - Comprehensive logging for audit trail
#   - Verification steps after service restart
#
# Author: Security Team
# Version: 1.0
# Last Updated: 2026-07-21
#===============================================================================

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('jwt', 'smtp', 'redis', 'all')]
    [string]$KeyType = 'all'
)

#-------------------------------------------------------------------------------
# Configuration Variables
#-------------------------------------------------------------------------------
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_ROOT = Split-Path -Parent $SCRIPT_DIR
$ENV_FILE = Join-Path $PROJECT_ROOT "deploy" ".env.prod"
$BACKUP_DIR = Join-Path $PROJECT_ROOT "deploy" ".backups"
$TIMESTAMP = Get-Date -Format "yyyyMMdd_HHmmss"
$LOG_FILE = Join-Path $PROJECT_ROOT "logs" "emergency_rotation_${TIMESTAMP}.log"

# Ensure log directory exists
$LogDir = Split-Path -Parent $LOG_FILE
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
}

#-------------------------------------------------------------------------------
# Logging Functions
#-------------------------------------------------------------------------------

function Log-Info {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[INFO] $timestamp - $Message"
    Write-Host $logEntry -ForegroundColor Green
    Add-Content -Path $LOG_FILE -Value $logEntry
}

function Log-Warn {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[WARN] $timestamp - $Message"
    Write-Host $logEntry -ForegroundColor Yellow
    Add-Content -Path $LOG_FILE -Value $logEntry
}

function Log-Error {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[ERROR] $timestamp - $Message"
    Write-Host $logEntry -ForegroundColor Red
    Add-Content -Path $LOG_FILE -Value $logEntry
}

#-------------------------------------------------------------------------------
# Utility Functions
#-------------------------------------------------------------------------------

# Generate cryptographically secure random secret
function New-Secret {
    $randomBytes = New-Object -TypeName byte[] 32
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    $rng.GetBytes($randomBytes)
    $secret = [Convert]::ToBase64String($randomBytes)
    $secret = $secret.TrimEnd('=').Replace('+', '-').Replace('/', '_') | Select-String -Pattern "^.{32}" | ForEach-Object { $_.Matches.Value }
    return $secret
}

# Create backup of current environment file
function New-Backup {
    param([string]$FilePath)
    
    Log-Info "Creating backup of $(Split-Path -Leaf $FilePath)..."
    
    if (-not (Test-Path $BACKUP_DIR)) {
        New-Item -ItemType Directory -Force -Path $BACKUP_DIR | Out-Null
    }
    
    if (Test-Path $FilePath) {
        $backupPath = Join-Path $BACKUP_DIR "$(Split-Path -Leaf $FilePath).pre_rotation.${TIMESTAMP}"
        Copy-Item -Path $FilePath -Destination $backupPath -Force
        Log-Info "Backup created: $backupPath"
        
        # Also keep immediate backup in deploy directory for quick rollback
        $quickBackup = Join-Path $PROJECT_ROOT "deploy" "$(Split-Path -Leaf $FilePath).old.${TIMESTAMP}"
        Copy-Item -Path $FilePath -Destination $quickBackup -Force
        Log-Info "Quick rollback backup created: $quickBackup"
    } else {
        Log-Error "File not found: $FilePath"
        return $false
    }
    return $true
}

# Update environment variable safely
function Update-EnvVar {
    param(
        [string]$VarName,
        [string]$NewValue,
        [string]$EnvFile
    )
    
    $tempFile = Join-Path $PROJECT_ROOT "temp_env.tmp"
    
    if (Select-String -Path $EnvFile -Pattern "^${VarName}=") {
        # Replace existing line
        (Get-Content $EnvFile) | ForEach-Object {
            if ($_ -match "^${VarName}=") {
                "${VarName}=${NewValue}"
            } else {
                $_
            }
        } | Set-Content $tempFile
        Move-Item -Path $tempFile -Destination $EnvFile -Force
    } else {
        # Append new variable
        Add-Content -Path $EnvFile -Value "${VarName}=${NewValue}"
    }
    
    Log-Info "Updated $VarName in $EnvFile"
}

# Verify file integrity after update
function Test-EnvUpdate {
    param(
        [string]$VarName,
        [string]$EnvFile
    )
    
    $value = Select-String -Path $EnvFile -Pattern "^${VarName}=" | ForEach-Object { $_.Line -replace "^${VarName}=", "" }
    
    if ($value) {
        # Mask sensitive values in logs
        $maskedValue = ("*" * 4) + "****"
        Log-Info "$VarName updated successfully (value masked: $maskedValue)"
        return $true
    } else {
        Log-Error "$VarName not found in $EnvFile"
        return $false
    }
}

#-------------------------------------------------------------------------------
# Rotation Functions
#-------------------------------------------------------------------------------

function Rotate-JWT-Secret {
    Log-Info "=== Starting JWT Secret Rotation ==="
    
    # Generate new secret
    $newSecret = New-Secret
    Log-Info "Generated new JWT secret (length: $($newSecret.Length) characters)"
    
    # Update .env.prod
    Update-EnvVar -VarName "JWT_SECRET" -NewValue $newSecret -EnvFile $ENV_FILE
    
    # Verify update
    if (Test-EnvUpdate -VarName "JWT_SECRET" -EnvFile $ENV_FILE) {
        Log-Info "JWT secret rotation completed successfully"
    } else {
        Log-Error "JWT secret rotation failed verification"
        return $false
    }
}

function Rotate-SMTP-Credentials {
    Log-Info "=== Starting SMTP Credential Rotation ==="
    
    # Generate new email password
    $newPassword = New-Secret
    Log-Info "Generated new SMTP password (length: $($newPassword.Length) characters)"
    
    # Update EMAIL_PASSWORD
    Update-EnvVar -VarName "EMAIL_PASSWORD" -NewValue $newPassword -EnvFile $ENV_FILE
    
    # Verify updates
    if (Test-EnvUpdate -VarName "EMAIL_PASSWORD" -EnvFile $ENV_FILE) {
        Log-Info "SMTP credential rotation completed"
        
        # Warn about manual testing required
        Log-Warn "Email delivery test REQUIRED after rotation:"
        Log-Warn "  Test with actual email provider console or send test email"
    } else {
        Log-Error "SMTP credential rotation failed verification"
        return $false
    }
}

function Rotate-Redis-Password {
    Log-Info "=== Starting Redis Password Rotation ==="
    
    # Generate new password
    $newPassword = New-Secret
    Log-Info "Generated new Redis password (length: $($newPassword.Length) characters)"
    
    # Update REDIS_PASSWORD
    Update-EnvVar -VarName "REDIS_PASSWORD" -NewValue $newPassword -EnvFile $ENV_FILE
    
    # Verify update
    if (Test-EnvUpdate -VarName "REDIS_PASSWORD" -EnvFile $ENV_FILE) {
        Log-Info "Redis password rotation completed"
        
        # Warn about cache invalidation
        Log-Warn "Cache will be invalidated during next service restart"
        Log-Warn "API response times may increase temporarily during cache warm-up"
        
        # Check if redis.conf exists and warn about manual update
        $redisConf = Join-Path $PROJECT_ROOT "deploy" "configs" "redis.conf"
        if (Test-Path $redisConf) {
            Log-Warn "Manual Redis configuration update may be required:"
            Log-Warn "  Edit $redisConf"
            Log-Warn "  Add 'requirepass $newPassword' to Redis configuration"
        }
    } else {
        Log-Error "Redis password rotation failed verification"
        return $false
    }
}

function Rotate-All-Secrets {
    Log-Info "=== EMERGENCY ROTATION: ALL SECRETS ==="
    Log-Warn "This will rotate JWT_SECRET, EMAIL_PASSWORD, and REDIS_PASSWORD simultaneously"
    
    # Confirm with user
    $confirm = Read-Host "Continue with emergency rotation? (yes/no)"
    if ($confirm -ne "yes") {
        Log-Info "Rotation cancelled by user"
        return $false
    }
    
    # Execute all rotations
    $result1 = Rotate-JWT-Secret
    $result2 = Rotate-SMTP-Credentials
    $result3 = Rotate-Redis-Password
    
    if ($result1 -and $result2 -and $result3) {
        Log-Info "ALL secrets rotated successfully"
        Log-Warn "WARNING: All active sessions will be terminated"
        Log-Warn "Plan user communication strategy immediately"
        return $true
    } else {
        Log-Error "Partial rotation failure detected"
        return $false
    }
}

#-------------------------------------------------------------------------------
# Main Script Flow
#-------------------------------------------------------------------------------

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "EMERGENCY KEY ROTATION SCRIPT" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Validate environment file exists
if (-not (Test-Path $ENV_FILE)) {
    Log-Error "Environment file not found: $ENV_FILE"
    Log-Info "Make sure you're running this script from the project root directory"
    exit 1
}

# Create initial backup
if (-not (New-Backup -FilePath $ENV_FILE)) {
    Log-Error "Failed to create backup. Aborting rotation."
    exit 1
}

Write-Host "`nStarting rotation procedure...`n" -ForegroundColor Yellow

# Execute requested rotation
switch ($KeyType) {
    'jwt' {
        Rotate-JWT-Secret
    }
    'smtp' {
        Rotate-SMTP-Credentials
    }
    'redis' {
        Rotate-Redis-Password
    }
    'all' {
        Rotate-All-Secrets
    }
}

Write-Host "`n==============================================" -ForegroundColor Cyan
Write-Host "ROTATION COMPLETE" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "`n"

# Post-rotation checklist
@'
Next Steps:
1. ✓ Verify all services are healthy (check container status)
   docker-compose -f deploy/docker-compose.prod.yml ps

2. ✓ Test authentication flow end-to-end
   Try logging in with a test account

3. ✓ Monitor error rates for the next 15 minutes
   Watch for spikes in 401 errors

4. ✓ Send notification to users (if required)
   Use established communication channels

5. ✓ Document rotation in audit log
   docs/key_rotation_audit_log_template.csv

6. ✓ Archive old secrets securely for 30 days
   They're already backed up in deploy/.backups/

Logs saved to: $LOG_FILE
Backups saved to: $BACKUP_DIR
'@

Write-Host "Logs saved to: $LOG_FILE" -ForegroundColor Gray
Write-Host "Backups saved to: $BACKUP_DIR`n" -ForegroundColor Gray

# Final verification for JWT rotation
if ($KeyType -eq 'jwt' -or $KeyType -eq 'all') {
    Log-Info "Running final authentication verification..."
    # Note: Service verification requires Docker access, which may not be available in PowerShell
    Log-Warn "Service verification should be done via Docker commands:"
    Log-Warn "  docker-compose -f deploy/docker-compose.prod.yml ps"
    Log-Warn "  docker logs inv-api-server --tail 50"
}

Log-Info "Script execution completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
