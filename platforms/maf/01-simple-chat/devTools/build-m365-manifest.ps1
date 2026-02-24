param(
    [string]$EnvironmentFile = "../../../../.env",
    [string]$TemplateFile = "./manifest.template.json",
    [string]$OutputFolder = "../dist/m365-manifest",
    [string]$PackageVersion = "1.0.0"
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

$envFilePath = Resolve-ModulePath $EnvironmentFile
$templatePath = Resolve-ModulePath $TemplateFile
$outputPath = Resolve-ModulePath $OutputFolder
$stagingPath = Join-Path $outputPath "staging"

$envValues = Read-EnvFile -envPath $envFilePath
$botAppId = Require-Value -source $envValues -key "MICROSOFT_APP_ID"
$agentHost = if ($envValues.ContainsKey("AGENT_HOST")) { $envValues["AGENT_HOST"] } else { "localhost" }

$parsedGuid = [Guid]::Empty
if (-not [Guid]::TryParse($botAppId, [ref]$parsedGuid)) {
    throw "MICROSOFT_APP_ID no tiene formato GUID válido: $botAppId"
}

New-Item -ItemType Directory -Path $stagingPath -Force | Out-Null

$template = Get-Content -LiteralPath $templatePath -Raw | ConvertFrom-Json

$template.version = $PackageVersion
$template.id = $botAppId
if ($template.bots.Count -lt 1) {
    throw "La plantilla no contiene definición de bots."
}
$template.bots[0].botId = $botAppId
$template.validDomains = @($agentHost)

$colorIconPath = Join-Path $stagingPath $template.icons.color
$outlineIconPath = Join-Path $stagingPath $template.icons.outline
Ensure-PathExists -path $colorIconPath -label "Icono color"
Ensure-PathExists -path $outlineIconPath -label "Icono outline"

$manifest = $template
$manifestPath = Join-Path $stagingPath "manifest.json"
$manifest | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

if (-not (Test-Path -LiteralPath $outputPath)) {
    New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
}

$zipPath = Join-Path $outputPath "simple-chat-agent-m365-manifest.zip"
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Compress-Archive -Path (Join-Path $stagingPath "*") -DestinationPath $zipPath -CompressionLevel Optimal

Write-Host "Manifest generado: $manifestPath"
Write-Host "Paquete generado: $zipPath"