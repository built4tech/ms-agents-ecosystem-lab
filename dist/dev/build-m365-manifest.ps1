param(
    [string]$EnvironmentFile = "../../.env",
    [string]$TemplateFile = "./manifest.template.json",
    [string]$OutputFolder = "../../dist/m365-manifest",
    [string]$PackageVersion = "1.0.0",
    [string]$ColorIconFile = "../../dist/m365-manifest/staging/color.png",
    [string]$OutlineIconFile = "../../dist/m365-manifest/staging/outline.png",
    [string]$DeployOutputFolder = "../../dist/deploy",
    [string]$WebAppName = "",
    [string]$ResourceGroup = "",
    [switch]$SkipWebAppDeploy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ModulePath([string]$relativePath) {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $relativePath))
}

function Read-EnvFile([string]$envPath) {
    if (-not (Test-Path -LiteralPath $envPath)) {
        throw "No se encontró archivo de entorno: $envPath"
    }

    $values = @{}

    foreach ($line in (Get-Content -LiteralPath $envPath)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $trimmed = $line.Trim()
        if ($trimmed.StartsWith("#")) {
            continue
        }

        $parts = $trimmed -split "=", 2
        if ($parts.Count -ne 2) {
            continue
        }

        $key = $parts[0].Trim()
        $value = $parts[1].Trim()
        if ($value.StartsWith('"') -and $value.EndsWith('"') -and $value.Length -ge 2) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $values[$key] = $value
    }

    return $values
}

function Require-Value([hashtable]$source, [string]$key) {
    if (-not $source.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($source[$key])) {
        throw "Variable requerida ausente o vacía en .env: $key"
    }
    return $source[$key]
}

function Ensure-PathExists([string]$path, [string]$label) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "$label no encontrado: $path"
    }
}

function Assert-AzSuccess([string]$message) {
    if ($LASTEXITCODE -ne 0) {
        throw $message
    }
}

function Copy-IfDifferent {
    param(
        [string]$Source,
        [string]$Destination
    )

    $sourceFull = [System.IO.Path]::GetFullPath($Source)
    $destinationFull = [System.IO.Path]::GetFullPath($Destination)

    if ($sourceFull -ieq $destinationFull) {
        return
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function To-Slug([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) {
        return ""
    }

    $slug = $value.ToLowerInvariant()
    $slug = [regex]::Replace($slug, "[^a-z0-9]+", "-")
    $slug = $slug.Trim("-")
    return $slug
}

$envFilePath = Resolve-ModulePath $EnvironmentFile
$templatePath = Resolve-ModulePath $TemplateFile
$outputPath = Resolve-ModulePath $OutputFolder
$manifestStagingPath = Join-Path $outputPath "staging"
$colorIconSourcePath = Resolve-ModulePath $ColorIconFile
$outlineIconSourcePath = Resolve-ModulePath $OutlineIconFile
$deployOutputPath = Resolve-ModulePath $DeployOutputFolder
$repoRoot = Resolve-ModulePath "../../"

$envValues = Read-EnvFile -envPath $envFilePath
$botAppId = Require-Value -source $envValues -key "MICROSOFT_APP_ID"
$agentHost = if ($envValues.ContainsKey("AGENT_HOST")) { $envValues["AGENT_HOST"] } else { "localhost" }
$webAppNameEffective = if ([string]::IsNullOrWhiteSpace($WebAppName)) {
    if ($envValues.ContainsKey("WEB_APP_NAME") -and -not [string]::IsNullOrWhiteSpace($envValues["WEB_APP_NAME"])) {
        $envValues["WEB_APP_NAME"]
    } else {
        ""
    }
} else {
    $WebAppName
}
$resourceGroupEffective = if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
    if ($envValues.ContainsKey("AZURE_RESOURCE_GROUP")) { $envValues["AZURE_RESOURCE_GROUP"] } else { "" }
} else {
    $ResourceGroup
}

if ([string]::IsNullOrWhiteSpace($webAppNameEffective)) {
    throw "No se pudo determinar WebAppName. Define WEB_APP_NAME en .env o pasa -WebAppName explícitamente."
}

$parsedGuid = [Guid]::Empty
if (-not [Guid]::TryParse($botAppId, [ref]$parsedGuid)) {
    throw "MICROSOFT_APP_ID no tiene formato GUID válido: $botAppId"
}

New-Item -ItemType Directory -Path $manifestStagingPath -Force | Out-Null

Ensure-PathExists -path $colorIconSourcePath -label "Icono color origen"
Ensure-PathExists -path $outlineIconSourcePath -label "Icono outline origen"

Copy-IfDifferent -Source $colorIconSourcePath -Destination (Join-Path $manifestStagingPath "color.png")
Copy-IfDifferent -Source $outlineIconSourcePath -Destination (Join-Path $manifestStagingPath "outline.png")

$template = Get-Content -LiteralPath $templatePath -Raw | ConvertFrom-Json

$template.version = $PackageVersion
$template.id = $botAppId
if ($template.bots.Count -lt 1) {
    throw "La plantilla no contiene definición de bots."
}
$template.bots[0].botId = $botAppId
$template.validDomains = @($agentHost)

$colorIconPath = Join-Path $manifestStagingPath $template.icons.color
$outlineIconPath = Join-Path $manifestStagingPath $template.icons.outline
Ensure-PathExists -path $colorIconPath -label "Icono color"
Ensure-PathExists -path $outlineIconPath -label "Icono outline"

$manifest = $template
$manifestPath = Join-Path $manifestStagingPath "manifest.json"
$manifest | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$projectName = if ($envValues.ContainsKey("PROJECT_NAME")) { $envValues["PROJECT_NAME"] } else { "" }
if ([string]::IsNullOrWhiteSpace($projectName) -and $template.name -and $template.name.short) {
    $projectName = [string]$template.name.short
}

$projectSlug = To-Slug $projectName
if ([string]::IsNullOrWhiteSpace($projectSlug)) {
    $projectSlug = "m365-agent"
}

if (-not (Test-Path -LiteralPath $outputPath)) {
    New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
}

$zipPath = Join-Path $outputPath "$projectSlug-m365-manifest.zip"
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Compress-Archive -Path (Join-Path $manifestStagingPath "*") -DestinationPath $zipPath -CompressionLevel Optimal

if (-not (Test-Path -LiteralPath $deployOutputPath)) {
    New-Item -ItemType Directory -Path $deployOutputPath -Force | Out-Null
}

$appStagingPath = Join-Path $deployOutputPath "staging-webapp"
if (Test-Path -LiteralPath $appStagingPath) {
    Remove-Item -LiteralPath $appStagingPath -Recurse -Force
}
New-Item -ItemType Directory -Path $appStagingPath -Force | Out-Null

$appSourcePath = Join-Path $repoRoot "app"
$mainPyPath = Join-Path $repoRoot "main.py"
$mainM365PyPath = Join-Path $repoRoot "main_m365.py"
$requirementsPath = Join-Path $repoRoot "requirements.txt"

Ensure-PathExists -path $appSourcePath -label "Carpeta app"
Ensure-PathExists -path $mainPyPath -label "main.py"
Ensure-PathExists -path $mainM365PyPath -label "main_m365.py"
Ensure-PathExists -path $requirementsPath -label "requirements.txt"

Copy-Item -LiteralPath $appSourcePath -Destination (Join-Path $appStagingPath "app") -Recurse -Force
Copy-Item -LiteralPath $mainPyPath -Destination (Join-Path $appStagingPath "main.py") -Force
Copy-Item -LiteralPath $mainM365PyPath -Destination (Join-Path $appStagingPath "main_m365.py") -Force
Copy-Item -LiteralPath $requirementsPath -Destination (Join-Path $appStagingPath "requirements.txt") -Force

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$appZipPath = Join-Path $deployOutputPath "$projectSlug-appservice-$timestamp.zip"
if (Test-Path -LiteralPath $appZipPath) {
    Remove-Item -LiteralPath $appZipPath -Force
}

Compress-Archive -Path (Join-Path $appStagingPath "*") -DestinationPath $appZipPath -CompressionLevel Optimal

$deployStatus = "OMITIDO"
if (-not $SkipWebAppDeploy.IsPresent) {
    if ([string]::IsNullOrWhiteSpace($resourceGroupEffective)) {
        throw "No se pudo determinar Resource Group. Pasa -ResourceGroup o define AZURE_RESOURCE_GROUP en .env"
    }

    $azAccount = az account show --output json 2>$null
    Assert-AzSuccess -message "No hay sesión activa en Azure CLI. Ejecuta 'az login'."

    az webapp deploy `
        --resource-group $resourceGroupEffective `
        --name $webAppNameEffective `
        --src-path $appZipPath `
        --type zip `
        --clean true `
        --restart true `
        --output table
    Assert-AzSuccess -message "Falló el deployment del paquete App Service en '$webAppNameEffective'."
    $deployStatus = "OK"
}

Write-Host "Manifest generado: $manifestPath"
Write-Host "Paquete manifest: $zipPath"
Write-Host "Paquete appservice: $appZipPath"
Write-Host "WebApp: $webAppNameEffective"
Write-Host "ResourceGroup: $resourceGroupEffective"
Write-Host "Deployment appservice: $deployStatus"