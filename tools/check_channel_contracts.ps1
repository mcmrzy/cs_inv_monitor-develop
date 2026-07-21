[CmdletBinding()]
param(
    [ValidateSet('legacy', 'shadow', 'enforce')]
    [string]$Mode = 'shadow',

    [string]$BaselinePath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$openApiRelativePath = 'contracts/openapi/channel-platform-v1.yaml'
$eventSchemaRelativePaths = @(
    'contracts/events/authorization-cache-invalidated.v1.schema.json',
    'contracts/events/asset-transfer.v1.schema.json',
    'contracts/events/audit-event.v1.schema.json'
)

function Resolve-ContractPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required contract asset is missing: $RelativePath"
    }
    return $path
}

function Assert-ContainsAll {
    param(
        [Parameter(Mandatory = $true)][object[]]$Actual,
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Subject
    )

    foreach ($item in $Expected) {
        if ($Actual -notcontains $item) {
            throw "$Subject is missing required value '$item'."
        }
    }
}

function ConvertFrom-SimpleYamlScalar {
    param([Parameter(Mandatory = $true)][string]$Value)

    $result = ($Value -split '\s+#', 2)[0].Trim().TrimEnd(',')
    if ($result.Length -ge 2) {
        if (($result.StartsWith("'") -and $result.EndsWith("'")) -or
            ($result.StartsWith('"') -and $result.EndsWith('"'))) {
            $result = $result.Substring(1, $result.Length - 2)
        }
    }
    return $result
}

function Get-YamlListValues {
    param(
        [Parameter(Mandatory = $true)][string[]]$Lines,
        [Parameter(Mandatory = $true)][int]$Index,
        [Parameter(Mandatory = $true)][int]$Indent,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$InlineValue
    )

    $values = New-Object System.Collections.Generic.List[string]
    $trimmed = $InlineValue.Trim()
    if ($trimmed -match '^\[(?<items>.*)\]$') {
        foreach ($item in ($Matches['items'] -split ',')) {
            $value = ConvertFrom-SimpleYamlScalar $item
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $values.Add($value) | Out-Null
            }
        }
    }
    else {
        for ($cursor = $Index + 1; $cursor -lt $Lines.Count; $cursor++) {
            $candidate = $Lines[$cursor]
            if ($candidate -match '^(?<space>\s+)-\s+(?<value>[^#]+?)\s*$' -and $Matches['space'].Length -gt $Indent) {
                $values.Add((ConvertFrom-SimpleYamlScalar $Matches['value'])) | Out-Null
                continue
            }
            if ([string]::IsNullOrWhiteSpace($candidate) -or $candidate.TrimStart().StartsWith('#')) {
                continue
            }
            break
        }
    }
    return @($values)
}

function Get-OpenApiMetadata {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "OpenAPI document was not found: $Path"
    }
    $lines = @(Get-Content -LiteralPath $Path)
    $operations = @{}
    $schemaNames = @{}
    $enums = @{}
    $requiredFields = @{}

    $currentPath = $null
    $currentOperation = $null
    foreach ($line in $lines) {
        if ($line -match '^  (?<path>/[^:]+):\s*$') {
            $currentPath = $Matches['path']
            $currentOperation = $null
            continue
        }
        if ($null -ne $currentPath -and $line -match '^    (?<method>get|post|put|patch|delete):\s*$') {
            $operationKey = '{0} {1}' -f $Matches['method'].ToUpperInvariant(), $currentPath
            $currentOperation = [pscustomobject]@{
                Method = $Matches['method'].ToUpperInvariant()
                Path = $currentPath
                Deprecated = $false
                Replacement = ''
            }
            $operations[$operationKey] = $currentOperation
            continue
        }
        if ($null -ne $currentOperation -and $line -match '^      deprecated:\s+true\s*$') {
            $currentOperation.Deprecated = $true
            continue
        }
        if ($null -ne $currentOperation -and $line -match '^      x-replacement:\s*(?<value>.+?)\s*$') {
            $currentOperation.Replacement = ConvertFrom-SimpleYamlScalar $Matches['value']
            continue
        }
        if ($line -match '^\S') {
            $currentPath = $null
            $currentOperation = $null
        }
    }

    $inSchemas = $false
    $currentSchema = $null
    $keyStack = @{}
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ($line -match '^  schemas:\s*$') {
            $inSchemas = $true
            continue
        }
        if (-not $inSchemas) {
            continue
        }
        if ($line -match '^    (?<schema>[A-Za-z0-9_.-]+):\s*$') {
            $currentSchema = $Matches['schema']
            $schemaNames[$currentSchema] = $true
            $keyStack = @{}
            continue
        }
        if ($null -eq $currentSchema) {
            continue
        }
        if ($line -match '^\S') {
            break
        }
        if ($line -notmatch '^(?<space>\s+)(?<key>[A-Za-z0-9_.$-]+):\s*(?<value>.*)$') {
            continue
        }

        $indent = $Matches['space'].Length
        if ($indent -le 4) {
            continue
        }
        $key = $Matches['key']
        $inlineValue = $Matches['value']
        foreach ($stackIndent in @($keyStack.Keys)) {
            if ([int]$stackIndent -ge $indent) {
                $keyStack.Remove($stackIndent)
            }
        }
        $ancestors = @($keyStack.Keys | Sort-Object { [int]$_ } | ForEach-Object { $keyStack[$_] })
        $context = '{0}/{1}/{2}' -f $currentSchema, ($ancestors -join '/'), $key
        if ($key -eq 'enum') {
            $enums[$context] = @(Get-YamlListValues -Lines $lines -Index $index -Indent $indent -InlineValue $inlineValue)
        }
        elseif ($key -eq 'required') {
            $requiredFields[$context] = @(Get-YamlListValues -Lines $lines -Index $index -Indent $indent -InlineValue $inlineValue)
        }
        $keyStack[$indent] = $key
    }

    return [pscustomobject]@{
        Operations = $operations
        SchemaNames = $schemaNames
        Enums = $enums
        RequiredFields = $requiredFields
    }
}

function Assert-BaselineCompatible {
    param(
        [Parameter(Mandatory = $true)]$Current,
        [Parameter(Mandatory = $true)]$Baseline
    )

    $breaks = New-Object System.Collections.Generic.List[string]
    foreach ($operation in $Baseline.Operations.Keys) {
        if (-not $Current.Operations.ContainsKey($operation)) {
            $breaks.Add("operation removed: $operation") | Out-Null
        }
    }
    foreach ($context in $Baseline.Enums.Keys) {
        $currentValues = @()
        if ($Current.Enums.ContainsKey($context)) {
            $currentValues = @($Current.Enums[$context])
        }
        foreach ($value in @($Baseline.Enums[$context])) {
            if ($currentValues -notcontains $value) {
                $breaks.Add("enum value removed: $context=$value") | Out-Null
            }
        }
    }
    foreach ($context in $Current.RequiredFields.Keys) {
        if (-not $Baseline.RequiredFields.ContainsKey($context)) {
            continue
        }
        $baselineValues = @($Baseline.RequiredFields[$context])
        foreach ($value in @($Current.RequiredFields[$context])) {
            if ($baselineValues -notcontains $value) {
                $breaks.Add("required field added: $context=$value") | Out-Null
            }
        }
    }
    if ($breaks.Count -gt 0) {
        throw "Baseline compatibility failure: $($breaks -join '; ')"
    }
}

function Get-RouteShape {
    param([Parameter(Mandatory = $true)][string]$Path)

    $shape = [regex]::Replace($Path, '\{[^/}]+\}', '{}')
    return [regex]::Replace($shape, ':[A-Za-z_][A-Za-z0-9_]*', '{}')
}

function Normalize-ApiPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $normalized = $Path.Trim()
    $normalized = [regex]::Replace($normalized, '\$\{[^}]+\}', '{parameter}')
    $normalized = [regex]::Replace($normalized, '\$[A-Za-z_][A-Za-z0-9_]*', '{parameter}')
    $normalized = ($normalized -split '\?', 2)[0]
    if ($normalized -match '[\$=\s]' -or $normalized -match '\{[^/}]*$') {
        return $null
    }
    if ($normalized.StartsWith('/api/v1', [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalized = $normalized.Substring('/api/v1'.Length)
    }
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return '/'
    }
    return $normalized
}

function Test-IsChannelClientPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return $Path -match '^/auth/context$' -or
        $Path -match '^/authorization(?:/|$)' -or
        $Path -match '^/organizations(?:/|$)' -or
        $Path -match '^/invitations(?:/|$)' -or
        $Path -match '^/devices/(?:claims|bind)$' -or
        $Path -match '^/devices/[^/]+/(?:grants|transfers|unbind|request-unbind|unbind-requests)(?:/|$)' -or
        $Path -match '^/device-unbind-requests/[^/]+/(?:approve|reject)$' -or
        $Path -match '^/stations/[^/]+/transfers(?:/|$)' -or
        $Path -match '^/users(?:/|$)'
}

function Get-GatewayRoutes {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Gateway route source is missing: $Path"
    }
    $routes = @()
    $source = Get-Content -LiteralPath $Path -Raw
    $pattern = '(?m)\b(?:publicGroup|userGroup|adminGroup)\.(?<method>Any|GET|POST|PUT|PATCH|DELETE)\(\s*"(?<path>/api/v1/[^"]+)"'
    foreach ($match in [regex]::Matches($source, $pattern)) {
        $pathValue = Normalize-ApiPath $match.Groups['path'].Value
        $routes += [pscustomobject]@{
            Method = $match.Groups['method'].Value.ToUpperInvariant()
            Path = $pathValue
            Wildcard = $pathValue.EndsWith('/*action') -or $pathValue.EndsWith('/*')
        }
    }
    return $routes
}

function Test-GatewayCoversOperation {
    param(
        [Parameter(Mandatory = $true)]$Operation,
        [Parameter(Mandatory = $true)][object[]]$GatewayRoutes
    )

    $operationShape = Get-RouteShape $Operation.Path
    foreach ($route in $GatewayRoutes) {
        if ($route.Method -ne 'ANY' -and $route.Method -ne $Operation.Method) {
            continue
        }
        if ($route.Wildcard) {
            $prefix = $route.Path.Substring(0, $route.Path.LastIndexOf('/*'))
            if ($Operation.Path.StartsWith($prefix + '/', [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
            continue
        }
        if ((Get-RouteShape $route.Path) -eq $operationShape) {
            return $true
        }
    }
    return $false
}

$openApiPath = Resolve-ContractPath $openApiRelativePath
$openApiText = Get-Content -LiteralPath $openApiPath -Raw
if ($openApiText -notmatch '(?m)^openapi:\s+3\.1\.0\s*$') {
    throw "$openApiRelativePath must declare OpenAPI 3.1.0."
}
$currentMetadata = Get-OpenApiMetadata $openApiPath

$requiredOperations = @(
    'POST /auth/context',
    'GET /authorization/me',
    'GET /organizations',
    'POST /organizations',
    'GET /organizations/{id}/children',
    'GET /organizations/{id}/members',
    'GET /invitations',
    'POST /invitations',
    'POST /devices/claims',
    'GET /devices/{sn}/grants',
    'POST /devices/{sn}/grants',
    'GET /devices/{sn}/transfers',
    'POST /devices/{sn}/transfers',
    'GET /stations/{id}/transfers',
    'POST /stations/{id}/transfers',
    'POST /devices/bind',
    'POST /devices/{sn}/unbind',
    'DELETE /devices/{sn}/unbind',
    'POST /devices/{sn}/request-unbind',
    'GET /devices/{sn}/unbind-requests',
    'POST /devices/{sn}/unbind-requests',
    'POST /device-unbind-requests/{id}/approve',
    'POST /device-unbind-requests/{id}/reject',
    'GET /users',
    'POST /users'
)
Assert-ContainsAll -Actual @($currentMetadata.Operations.Keys) -Expected $requiredOperations -Subject $openApiRelativePath

foreach ($schemaName in @('PermissionScopeGrant', 'RoleAssignment', 'AuthorizationContextV2', 'DeviceResource', 'StationResource', 'UnbindRequest', 'DeviceTransfer', 'StationTransfer')) {
    if (-not $currentMetadata.SchemaNames.ContainsKey($schemaName)) {
        throw "$openApiRelativePath must declare schema '$schemaName'."
    }
}
foreach ($code in @('APPROVAL_REQUIRED', 'ASSET_CONFLICT', 'CLAIM_INVALID', 'CLAIM_REPLAYED', 'MEMBERSHIP_INACTIVE', 'ORG_SCOPE_DENIED', 'TRANSFER_PENDING', 'VERSION_CONFLICT')) {
    if ($openApiText -notmatch ('(?m)^\s+-\s+' + [regex]::Escape($code) + '\s*$')) {
        throw "$openApiRelativePath is missing stable business error code '$code'."
    }
}

$expectedPayloadFields = @{
    'contracts/events/authorization-cache-invalidated.v1.schema.json' = @('authorization_version', 'reason', 'scope')
    'contracts/events/asset-transfer.v1.schema.json' = @('transfer_id', 'asset_type', 'asset_id', 'from_organization_id', 'to_organization_id', 'status')
    'contracts/events/audit-event.v1.schema.json' = @('actor_user_id', 'active_organization_id', 'action', 'resource_type', 'resource_id', 'result', 'request_id', 'source_ip', 'before', 'after', 'failure_reason')
}
$commonEventFields = @('schema_version', 'event_id', 'occurred_at', 'root_tenant_id', 'payload')
foreach ($relativePath in $eventSchemaRelativePaths) {
    $schemaPath = Resolve-ContractPath $relativePath
    try {
        $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "$relativePath is not valid JSON: $($_.Exception.Message)"
    }
    $schemaDialectProperty = $schema.PSObject.Properties['$schema']
    if ($null -eq $schemaDialectProperty -or $schemaDialectProperty.Value -ne 'https://json-schema.org/draft/2020-12/schema') {
        throw "$relativePath must use JSON Schema draft 2020-12."
    }
    if ($schema.type -ne 'object' -or $schema.additionalProperties -ne $false) {
        throw "$relativePath must describe a closed event object."
    }
    Assert-ContainsAll -Actual @($schema.required) -Expected $commonEventFields -Subject "$relativePath required"
    Assert-ContainsAll -Actual @($schema.properties.PSObject.Properties.Name) -Expected $commonEventFields -Subject "$relativePath properties"
    if ($schema.properties.schema_version.const -ne '1.0') {
        throw "$relativePath must pin schema_version to 1.0."
    }
    if ($schema.properties.payload.type -ne 'object' -or $schema.properties.payload.additionalProperties -ne $false) {
        throw "$relativePath must declare a closed object payload."
    }
    Assert-ContainsAll -Actual @($schema.properties.payload.required) -Expected $expectedPayloadFields[$relativePath] -Subject "$relativePath payload.required"
    Assert-ContainsAll -Actual @($schema.properties.payload.properties.PSObject.Properties.Name) -Expected $expectedPayloadFields[$relativePath] -Subject "$relativePath payload.properties"
}

if (-not [string]::IsNullOrWhiteSpace($BaselinePath)) {
    $resolvedBaselinePath = $BaselinePath
    if (-not [System.IO.Path]::IsPathRooted($resolvedBaselinePath)) {
        $resolvedBaselinePath = Join-Path $repoRoot $resolvedBaselinePath
    }
    if (-not (Test-Path -LiteralPath $resolvedBaselinePath -PathType Leaf)) {
        throw "Baseline OpenAPI document was not found: $BaselinePath"
    }
    $baselineMetadata = Get-OpenApiMetadata $resolvedBaselinePath
    Assert-BaselineCompatible -Current $currentMetadata -Baseline $baselineMetadata
}

$gatewayRoutePath = Join-Path $repoRoot 'api-gateway/internal/routes/routes.go'
$gatewayRoutes = @(Get-GatewayRoutes $gatewayRoutePath)
$gatewayGaps = @{}
foreach ($operationKey in $currentMetadata.Operations.Keys) {
    $operation = $currentMetadata.Operations[$operationKey]
    if (-not (Test-GatewayCoversOperation -Operation $operation -GatewayRoutes $gatewayRoutes)) {
        $gatewayGaps[$operationKey] = $true
    }
}

$declaredShapes = @{}
$deprecatedShapes = @{}
foreach ($operationKey in $currentMetadata.Operations.Keys) {
    $operation = $currentMetadata.Operations[$operationKey]
    $shape = '{0} {1}' -f $operation.Method, (Get-RouteShape $operation.Path)
    $declaredShapes[$shape] = $operation
    if ($operation.Deprecated) {
        $deprecatedShapes[$shape] = $operation
    }
}

$scanTargets = @(
    [pscustomobject]@{ Root = Join-Path $repoRoot 'inv-admin-frontend/src'; Extensions = @('.ts', '.tsx') },
    [pscustomobject]@{ Root = Join-Path $repoRoot 'inv_app/lib'; Extensions = @('.dart') }
)
$literalCallPattern = @'
(?im)\b(?:api|dio|_dio|getIt<Dio>\(\))\s*\.\s*(?<method>get|post|put|patch|delete)\s*(?:<[^>\r\n]+>)?\s*\(\s*['"`](?<path>/[^'"`\r\n]+)
'@
$observedChannelOperations = @{}
$deprecatedClientOperations = @{}
$undocumentedClientOperations = @{}
foreach ($target in $scanTargets) {
    if (-not (Test-Path -LiteralPath $target.Root -PathType Container)) {
        continue
    }
    $sourceFiles = Get-ChildItem -LiteralPath $target.Root -Recurse -File | Where-Object {
        $target.Extensions -contains $_.Extension.ToLowerInvariant()
    }
    foreach ($sourceFile in $sourceFiles) {
        $relativeFile = $sourceFile.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
        if ($relativeFile -match '(^|[\\/])(?:test|tests|mocks?|fixtures)([\\/]|$)' -or
            $sourceFile.Name -match '\.(?:test|spec)\.[^.]+$' -or
            $sourceFile.Name -in @('local_communication_service.dart', 'local_firmware_service.dart')) {
            continue
        }
        $source = Get-Content -LiteralPath $sourceFile.FullName -Raw
        foreach ($match in [regex]::Matches($source, $literalCallPattern)) {
            $method = $match.Groups['method'].Value.ToUpperInvariant()
            $path = Normalize-ApiPath $match.Groups['path'].Value
            if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-IsChannelClientPath $path)) {
                continue
            }
            $operationKey = '{0} {1}' -f $method, $path
            $shape = '{0} {1}' -f $method, (Get-RouteShape $path)
            $observedChannelOperations[$operationKey] = $true
            if ($deprecatedShapes.ContainsKey($shape)) {
                if (-not $deprecatedClientOperations.ContainsKey($operationKey)) {
                    $deprecatedClientOperations[$operationKey] = [pscustomobject]@{
                        File = $relativeFile
                        Replacement = $deprecatedShapes[$shape].Replacement
                    }
                }
            }
            elseif (-not $declaredShapes.ContainsKey($shape) -and -not $undocumentedClientOperations.ContainsKey($operationKey)) {
                $undocumentedClientOperations[$operationKey] = $relativeFile
            }
        }
    }
}

if ($Mode -eq 'shadow' -or $Mode -eq 'enforce') {
    foreach ($operation in @($gatewayGaps.Keys | Sort-Object)) {
        Write-Warning "Gateway route missing: $operation"
    }
    foreach ($operation in @($deprecatedClientOperations.Keys | Sort-Object)) {
        $finding = $deprecatedClientOperations[$operation]
        Write-Warning ("Deprecated client call: {0}; replacement={1} ({2})" -f $operation, $finding.Replacement, $finding.File)
    }
    foreach ($operation in @($undocumentedClientOperations.Keys | Sort-Object)) {
        Write-Warning ("Undeclared channel client call: {0} ({1})" -f $operation, $undocumentedClientOperations[$operation])
    }
}

Write-Host ('[channel-contract] mode={0} declared={1} gateway_missing={2} channel_scanned={3} deprecated_clients={4} undeclared_clients={5}' -f `
    $Mode, $currentMetadata.Operations.Count, $gatewayGaps.Count, $observedChannelOperations.Count, $deprecatedClientOperations.Count, $undocumentedClientOperations.Count)

$blockingCount = $gatewayGaps.Count + $deprecatedClientOperations.Count + $undocumentedClientOperations.Count
if ($Mode -eq 'enforce' -and $blockingCount -gt 0) {
    throw "Channel contract enforcement failed: Gateway route missing=$($gatewayGaps.Count), deprecated client calls=$($deprecatedClientOperations.Count), undeclared channel client calls=$($undocumentedClientOperations.Count)."
}

Write-Host '[channel-contract] contract assets and required API/event surfaces are valid.'
