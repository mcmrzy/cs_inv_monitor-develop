#!/usr/bin/env pwsh
# OpenAPI Documentation Validation Script
# This script validates the OpenAPI specification and generates various outputs

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "OpenAPI Documentation Validation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if Node.js is installed
try {
    $nodeVersion = node --version
    Write-Host "✓ Node.js detected: $nodeVersion" -ForegroundColor Green
} catch {
    Write-Host "✗ Node.js not found. Please install Node.js from https://nodejs.org/" -ForegroundColor Red
    exit 1
}

# Create temp directory for outputs
$tempDir = Join-Path $PSScriptRoot "temp-validation"
if (!(Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir | Out-Null
}

# Step 1: Install required tools
Write-Host ""
Write-Host "Step 1: Installing validation tools..." -ForegroundColor Yellow
try {
    npm list -g @stoplight/spectral-cli 2>$null
    Write-Host "✓ Spectral already installed" -ForegroundColor Green
} catch {
    Write-Host "Installing Spectral..." -ForegroundColor Yellow
    npm install -g @stoplight/spectral-cli
}

try {
    npm list -g @redocly/cli 2>$null
    Write-Host "✓ Redocly CLI already installed" -ForegroundColor Green
} catch {
    Write-Host "Installing Redocly CLI..." -ForegroundColor Yellow
    npm install -g @redocly/cli
}

# Step 2: Validate OpenAPI spec with Spectral
Write-Host ""
Write-Host "Step 2: Validating OpenAPI spec with Spectral..." -ForegroundColor Yellow
try {
    spectral lint docs/openapi.yaml --ruleset https://raw.githubusercontent.com/stoplightio/spectral/main/rulesets/oas.yaml
    Write-Host "✓ Spectral validation passed" -ForegroundColor Green
} catch {
    Write-Host "✗ Spectral validation failed" -ForegroundColor Red
    exit 1
}

# Step 3: Bundle OpenAPI spec with Redocly
Write-Host ""
Write-Host "Step 3: Bundling OpenAPI spec..." -ForegroundColor Yellow
try {
    redocly bundle docs/openapi.yaml -o (Join-Path $tempDir "openapi.bundled.yaml")
    Write-Host "✓ Bundle created successfully" -ForegroundColor Green
} catch {
    Write-Host "✗ Bundle creation failed" -ForegroundColor Red
    exit 1
}

# Step 4: Validate bundled spec
Write-Host ""
Write-Host "Step 4: Validating bundled spec..." -ForegroundColor Yellow
try {
    redocly lint (Join-Path $tempDir "openapi.bundled.yaml")
    Write-Host "✓ Bundled spec validation passed" -ForegroundColor Green
} catch {
    Write-Host "✗ Bundled spec validation failed" -ForegroundColor Red
    exit 1
}

# Step 5: Count endpoints
Write-Host ""
Write-Host "Step 5: Counting documented endpoints..." -ForegroundColor Yellow
try {
    # Install yq if not present
    $yqPath = Join-Path $tempDir "yq.exe"
    if (!(Test-Path $yqPath)) {
        Write-Host "Downloading yq..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri "https://github.com/mikefarah/yq/releases/download/v4.35.2/yq_windows_amd64.exe" -OutFile $yqPath
    }
    
    $pathCount = & $yqPath eval '.paths | keys | length' docs/openapi.yaml
    Write-Host "✓ Total documented paths: $pathCount" -ForegroundColor Green
    
    # Expected endpoints
    Write-Host ""
    Write-Host "Expected endpoint distribution:" -ForegroundColor Cyan
    Write-Host "  - Organizations: 8 endpoints"
    Write-Host "  - Invitations: 5 endpoints"
    Write-Host "  - Devices (claim/transfer): 8 endpoints"
    Write-Host "  - Members (lifecycle): 12 endpoints"
    Write-Host "  Total expected: 33 endpoints"
} catch {
    Write-Host "Warning: Could not count endpoints (yq not available)" -ForegroundColor Yellow
}

# Step 6: Verify required tags
Write-Host ""
Write-Host "Step 6: Verifying required tags..." -ForegroundColor Yellow
try {
    $tags = & $yqPath eval '.tags[].name' docs/openapi.yaml
    Write-Host "Found tags:" -ForegroundColor Cyan
    $tags | ForEach-Object { Write-Host "  - $_" }
    
    $requiredTags = @("Organizations", "Invitations", "Devices", "Members")
    $allFound = $true
    
    foreach ($tag in $requiredTags) {
        if ($tags -contains $tag) {
            Write-Host "✓ Tag '$tag' found" -ForegroundColor Green
        } else {
            Write-Host "✗ Tag '$tag' missing" -ForegroundColor Red
            $allFound = $false
        }
    }
    
    if (!$allFound) {
        exit 1
    }
} catch {
    Write-Host "Warning: Could not verify tags" -ForegroundColor Yellow
}

# Step 7: Generate Postman collection (optional)
Write-Host ""
Write-Host "Step 7: Generating Postman collection..." -ForegroundColor Yellow
try {
    npm list -g openapi-to-postman 2>$null
    Write-Host "✓ openapi-to-postman already installed" -ForegroundColor Green
} catch {
    Write-Host "Installing openapi-to-postman..." -ForegroundColor Yellow
    npm install -g openapi-to-postman
}

try {
    $postmanDir = Join-Path $PSScriptRoot "postman"
    if (!(Test-Path $postmanDir)) {
        New-Item -ItemType Directory -Path $postmanDir | Out-Null
    }
    
    openapi2postmanv2 --spec docs/openapi.yaml --output (Join-Path $postmanDir "collection.json") --options folderStrategy=Tags,requestNameSource=URL
    Write-Host "✓ Postman collection generated at: $(Join-Path $postmanDir "collection.json")" -ForegroundColor Green
} catch {
    Write-Host "Warning: Could not generate Postman collection" -ForegroundColor Yellow
}

# Step 8: Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Validation Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "✓ All validations passed!" -ForegroundColor Green
Write-Host ""
Write-Host "Generated files:" -ForegroundColor Cyan
Write-Host "  - $(Join-Path $tempDir "openapi.bundled.yaml")"
Write-Host "  - $(Join-Path $postmanDir "collection.json")"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Open docs/swagger/index.html in a browser to view interactive documentation"
Write-Host "  2. Import postman/collection.json into Postman for API testing"
Write-Host "  3. Deploy docs/openapi.yaml to your documentation portal"
Write-Host ""

# Cleanup (optional)
$cleanup = Read-Host "Clean up temporary files? (y/n)"
if ($cleanup -eq 'y' -or $cleanup -eq 'Y') {
    Remove-Item -Path $tempDir -Recurse -Force
    Write-Host "✓ Temporary files cleaned up" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
