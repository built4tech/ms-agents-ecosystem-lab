param(
    [string]$EnvironmentFile = "../../.env",
    [string]$TemplateFile = "./manifest.template.json",
    [string]$OutputFolder = "../../dist/deploy/m365",
    [string]$PackageVersion = "1.0.0",
    [string]$ColorIconFile = "./assets/color.png",
    [string]$OutlineIconFile = "./assets/outline.png",
    [string]$DeployOutputFolder = "../../dist/deploy/webapp",
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

function Ensure-Directory([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
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

function Resolve-ValidDomain {
    param([hashtable]$EnvValues, [string]$AgentHost)

    if ($EnvValues.ContainsKey("AGENT_VALID_DOMAIN") -and -not [string]::IsNullOrWhiteSpace($EnvValues["AGENT_VALID_DOMAIN"])) {
        return $EnvValues["AGENT_VALID_DOMAIN"].Trim()
    }

    if ($EnvValues.ContainsKey("AGENT_MESSAGES_ENDPOINT") -and -not [string]::IsNullOrWhiteSpace($EnvValues["AGENT_MESSAGES_ENDPOINT"])) {
        $endpoint = $EnvValues["AGENT_MESSAGES_ENDPOINT"].Trim()
        try {
            $uri = [System.Uri]$endpoint
            if (-not [string]::IsNullOrWhiteSpace($uri.Host)) {
                return $uri.Host
            }
        } catch {
        }
    }

    if ($EnvValues.ContainsKey("WEB_APP_NAME") -and -not [string]::IsNullOrWhiteSpace($EnvValues["WEB_APP_NAME"])) {
        $webAppNameOrHost = $EnvValues["WEB_APP_NAME"].Trim()
        if ($webAppNameOrHost.Contains(".")) {
            return $webAppNameOrHost
        }
        return "$webAppNameOrHost.azurewebsites.net"
    }

    return $AgentHost
}

function Set-ManifestValidDomains {
    param(
        [string]$ManifestPath,
        [string]$Domain
    )

    $manifestJson = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    $manifestJson.validDomains = @($Domain)
    $manifestJson | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
}

$envFilePath = Resolve-ModulePath $EnvironmentFile
$templatePath = Resolve-ModulePath $TemplateFile
$m365OutputPath = Resolve-ModulePath $OutputFolder
$manifestStagingPath = Join-Path $m365OutputPath "manifest"
$manifestPackagePath = Join-Path $m365OutputPath "package"
$colorIconSourcePath = Resolve-ModulePath $ColorIconFile
$outlineIconSourcePath = Resolve-ModulePath $OutlineIconFile
$deployOutputPath = Resolve-ModulePath $DeployOutputFolder
$repoRoot = Resolve-ModulePath "../../"

$envValues = Read-EnvFile -envPath $envFilePath
$botAppId = Require-Value -source $envValues -key "MICROSOFT_APP_ID"
$agentHost = if ($envValues.ContainsKey("AGENT_HOST")) { $envValues["AGENT_HOST"] } else { "localhost" }
$agentValidDomain = Resolve-ValidDomain -EnvValues $envValues -AgentHost $agentHost
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

Ensure-Directory -path $m365OutputPath
Ensure-Directory -path $manifestStagingPath
Ensure-Directory -path $manifestPackagePath

Get-ChildItem -LiteralPath $manifestStagingPath -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in @("manifest.json", "agenticUserTemplateManifest.json") } |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

$manifestColorIconPath = Join-Path $manifestStagingPath "color.png"
$manifestOutlineIconPath = Join-Path $manifestStagingPath "outline.png"

if (Test-Path -LiteralPath $colorIconSourcePath) {
    Copy-IfDifferent -Source $colorIconSourcePath -Destination $manifestColorIconPath
} else {
    throw "Icono color origen no encontrado: $colorIconSourcePath"
}

if (Test-Path -LiteralPath $outlineIconSourcePath) {
    Copy-IfDifferent -Source $outlineIconSourcePath -Destination $manifestOutlineIconPath
} else {
    throw "Icono outline origen no encontrado: $outlineIconSourcePath"
}

$template = Get-Content -LiteralPath $templatePath -Raw | ConvertFrom-Json

$template.version = $PackageVersion
$template.id = $botAppId
if ($template.bots.Count -lt 1) {
    throw "La plantilla no contiene definición de bots."
}
$template.bots[0].botId = $botAppId

if ($template.PSObject.Properties.Name -contains "copilotAgents") {
    $copilotAgents = $template.copilotAgents
    if ($null -ne $copilotAgents -and ($copilotAgents.PSObject.Properties.Name -contains "customEngineAgents")) {
        foreach ($agent in $copilotAgents.customEngineAgents) {
            if ($null -ne $agent -and ($agent.PSObject.Properties.Name -contains "id")) {
                $agent.id = $botAppId
            }
        }
    }
}

$template.validDomains = @($agentValidDomain)

$colorIconPath = Join-Path $manifestStagingPath $template.icons.color
$outlineIconPath = Join-Path $manifestStagingPath $template.icons.outline
Ensure-PathExists -path $colorIconPath -label "Icono color"
Ensure-PathExists -path $outlineIconPath -label "Icono outline"

$manifest = $template
$manifestPath = Join-Path $manifestStagingPath "manifest.json"
$agenticUserTemplateManifestPath = Join-Path $manifestStagingPath "agenticUserTemplateManifest.json"
$manifest | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
$manifest | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $agenticUserTemplateManifestPath -Encoding UTF8

Set-ManifestValidDomains -ManifestPath $manifestPath -Domain $agentValidDomain
Set-ManifestValidDomains -ManifestPath $agenticUserTemplateManifestPath -Domain $agentValidDomain

$projectName = if ($envValues.ContainsKey("PROJECT_NAME")) { $envValues["PROJECT_NAME"] } else { "" }
if ([string]::IsNullOrWhiteSpace($projectName) -and $template.name -and $template.name.short) {
    $projectName = [string]$template.name.short
}

$projectSlug = To-Slug $projectName
if ([string]::IsNullOrWhiteSpace($projectSlug)) {
    $projectSlug = "m365-agent"
}

$zipPath = Join-Path $manifestPackagePath "manifest.zip"
Get-ChildItem -LiteralPath $manifestPackagePath -File -Filter "*.zip" -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
}

Compress-Archive -Path (Join-Path $manifestStagingPath "*") -DestinationPath $zipPath -CompressionLevel Optimal

Ensure-Directory -path $deployOutputPath

$appStagingPath = Join-Path $deployOutputPath "staging"
$appPackagePath = Join-Path $deployOutputPath "package"
Ensure-Directory -path $appPackagePath
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

Get-ChildItem -LiteralPath (Join-Path $appStagingPath "app") -Directory -Filter "__pycache__" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
}
Get-ChildItem -LiteralPath $appStagingPath -File -Filter "*.pyc" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$appZipPath = Join-Path $appPackagePath "webapp.zip"
Get-ChildItem -LiteralPath $appPackagePath -File -Filter "*.zip" -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
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