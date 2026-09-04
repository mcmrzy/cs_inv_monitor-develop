$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$iconDirectory = Join-Path $repositoryRoot 'inv_app/assets/icons/csergy'
$requiredFiles = @(
  'nav_home_normal.svg',
  'nav_home_active.svg',
  'nav_statistics_normal.svg',
  'nav_statistics_active.svg',
  'nav_devices_normal.svg',
  'nav_devices_active.svg',
  'nav_alarms_normal.svg',
  'nav_alarms_active.svg',
  'nav_profile_normal.svg',
  'nav_profile_active.svg',
  'nav_ota_normal.svg',
  'nav_ota_active.svg',
  'solar.svg',
  'grid.svg',
  'battery.svg',
  'load.svg',
  'inverter.svg',
  'storage.svg',
  'wifi.svg',
  'firmware.svg',
  'energy_flow.svg',
  'monitoring.svg',
  'power.svg',
  'warning.svg'
)

if (-not (Test-Path -LiteralPath $iconDirectory)) {
  throw "Missing icon directory: $iconDirectory"
}

$missingFiles = @($requiredFiles | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $iconDirectory $_))
  })
if ($missingFiles.Count -gt 0) {
  throw "Missing required SVG files: $($missingFiles -join ', ')"
}

$validationErrors = @()
foreach ($fileName in $requiredFiles) {
  $filePath = Join-Path $iconDirectory $fileName
  $svgText = Get-Content -LiteralPath $filePath -Raw

  try {
    $xmlDocument = New-Object System.Xml.XmlDocument
    $xmlDocument.Load($filePath)
  } catch {
    $validationErrors += "${fileName}: invalid XML ($($_.Exception.Message))"
    continue
  }

  $rootElement = $xmlDocument.DocumentElement
  if ($rootElement.GetAttribute('viewBox') -ne '0 0 24 24') {
    $validationErrors += "${fileName}: viewBox must be 0 0 24 24"
  }
  if ($svgText -notmatch "currentColor") {
    $validationErrors += "${fileName}: missing currentColor for theme tinting"
  }
  if ($svgText -match '#1769E0|#32C7A5') {
    $validationErrors += "${fileName}: legacy palette value detected"
  }
}

$pubspecPath = Join-Path $repositoryRoot 'inv_app/pubspec.yaml'
$pubspecText = Get-Content -LiteralPath $pubspecPath -Raw
if ($pubspecText -notmatch '(?m)^\s+- assets/icons/csergy/\s*$') {
  $validationErrors += 'pubspec.yaml: assets/icons/csergy/ is not declared'
}

if ($validationErrors.Count -gt 0) {
  $validationErrors | ForEach-Object { Write-Error $_ }
  exit 1
}

Write-Output "CSERGY asset gate passed: $($requiredFiles.Count) SVG files and pubspec declaration verified."
