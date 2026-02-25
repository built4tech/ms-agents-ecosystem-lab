# ============================================================================
# 03-m365-service-principal.ps1 - Crear app registration + service principal
# multitenant y poblar variables MICROSOFT_APP_* en .env.generated
# ============================================================================

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptPath\..\config\lab-config.ps1"
. "$scriptPath\auth-permissions-helper.ps1"
. "$scriptPath\env-generated-helper.ps1"

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                  OBJETIVO DEL SCRIPT                         ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  1) Buscar/crear App Registration multitenant                " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  2) Buscar/crear Service Principal asociado                  " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  3) Generar secreto de cliente para la aplicación            " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  4) Persistir variables MICROSOFT_APP_* en .env.generated    " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan


function Mask-Secret {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "(vacío)" }
    if ($Value.Length -le 10) { return "********" }
    return "$($Value.Substring(0,4))...$($Value.Substring($Value.Length-4))"
}

$account = Assert-InfraPrerequisites -ForScript "03-m365-service-principal.ps1"

$m365DisplayName = if ($script:M365AppDisplayName) { $script:M365AppDisplayName } else { "agent-identities-viewer-m365" }
$tenantId = $account.tenantId
$appType = "MultiTenant"

Write-Host "`n$('='*60)" -ForegroundColor Cyan
Write-Host " APP REGISTRATION + SERVICE PRINCIPAL" -ForegroundColor Cyan
Write-Host $('='*60) -ForegroundColor Cyan

Write-Step "Buscando app registration '$m365DisplayName'..."
$existingApp = az ad app list --display-name $m365DisplayName --query "[0]" --output json | ConvertFrom-Json

if (-not $existingApp) {
    Write-Success "App registration no existente (se procederá a crear)"
    Write-Step "Creando app registration multitenant..."
    $newApp = az ad app create `
        --display-name $m365DisplayName `
        --sign-in-audience AzureADMultipleOrgs `
        --query "{appId:appId,id:id}" `
        --output json | ConvertFrom-Json
    $appId = $newApp.appId
    Write-Success "App registration creada"
} else {
    $appId = $existingApp.appId
    Write-Success "App registration existente detectada"
}

Write-Step "Asegurando service principal para AppId $appId..."
$spExists = az ad sp show --id $appId --output json 2>$null | ConvertFrom-Json
if (-not $spExists) {
    az ad sp create --id $appId --output none
    Write-Success "Service principal creado"
} else {
    Write-Success "Service principal ya existe"
}

Write-Step "Creando secreto de cliente para la app (rotación/append)..."
$secretDisplayName = "infra-generated-$(Get-Date -Format 'yyyyMMddHHmmss')"
$appPassword = az ad app credential reset `
    --id $appId `
    --append `
    --display-name $secretDisplayName `
    --years 2 `
    --query password `
    --output tsv

if ([string]::IsNullOrWhiteSpace($appPassword)) {
    Write-Error "No se pudo generar el secreto de cliente"
    exit 1
}
Write-Success "Secreto de cliente generado"

$agentHost = if ($script:AgentHost) { $script:AgentHost } else { "localhost" }
$agentPort = if ($script:AgentPort) { $script:AgentPort } else { "3978" }

$null = Update-EnvGeneratedSection -ScriptPath $scriptPath -SectionName "03-m365-service-principal.ps1" -SectionValues @{
    AGENT_HOST             = $agentHost
    PORT                   = $agentPort
    MICROSOFT_APP_ID       = $appId
    MICROSOFT_APP_PASSWORD = $appPassword
    MICROSOFT_APP_TYPE     = $appType
    MICROSOFT_APP_TENANTID = $tenantId
}

Write-Host "`n$('-'*60)" -ForegroundColor Gray
Write-Host " ACTUALIZACIÓN DE .env.generated" -ForegroundColor Yellow
Write-Host $('-'*60) -ForegroundColor Gray
Write-Endpoint "AGENT_HOST" $agentHost
Write-Endpoint "PORT" $agentPort
Write-Endpoint "MICROSOFT_APP_ID" $appId
Write-Endpoint "MICROSOFT_APP_PASSWORD" "(valor generado)"
Write-Endpoint "MICROSOFT_APP_TYPE" $appType
Write-Endpoint "MICROSOFT_APP_TENANTID" $tenantId