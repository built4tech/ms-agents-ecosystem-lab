# ============================================================================
# 06-bot-service.ps1 - Crear/configurar Azure Bot Service para enrutamiento
# Copilot/Teams hacia el endpoint /api/messages del runtime M365
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
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  1) Crear/reutilizar Azure Bot Service registration          " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  2) Vincular endpoint cloud del agente (/api/messages)       " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  3) Habilitar canal MsTeamsChannel                            " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  4) Persistir BOT_SERVICE_NAME y endpoint en .env.generated   " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

function Get-RepoRoot {
    return Split-Path -Parent (Split-Path -Parent $scriptPath)
}

function Parse-DotEnvFile {
    param([string]$Path)
    $result = @{}
    if (-not (Test-Path $Path)) { return $result }

    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith("#")) { return }
        if ($line -match '^\s*([^=]+)=(.*)$') {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim()
            $result[$name] = $value
        }
    }

    return $result
}

function Assert-AzSuccess {
    param([string]$Message)
    if ($LASTEXITCODE -ne 0) {
        throw $Message
    }
}

function Ensure-BotServiceProvider {
    $state = az provider show --namespace Microsoft.BotService --query registrationState --output tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($state)) {
        az provider register --namespace Microsoft.BotService --output none
        Assert-AzSuccess -Message "No se pudo registrar el proveedor Microsoft.BotService."
        return
    }

    if ($state -ne "Registered") {
        az provider register --namespace Microsoft.BotService --output none
        Assert-AzSuccess -Message "No se pudo registrar el proveedor Microsoft.BotService."
    }
}

function Resolve-AgentEndpoint {
    param(
        [hashtable]$EnvValues,
        [string]$ResourceGroup,
        [string]$DefaultWebAppName
    )

    if ($EnvValues.ContainsKey("AGENT_MESSAGES_ENDPOINT") -and -not [string]::IsNullOrWhiteSpace($EnvValues["AGENT_MESSAGES_ENDPOINT"])) {
        return $EnvValues["AGENT_MESSAGES_ENDPOINT"].Trim()
    }

    $webAppName = if ($EnvValues.ContainsKey("WEB_APP_NAME") -and -not [string]::IsNullOrWhiteSpace($EnvValues["WEB_APP_NAME"])) {
        $EnvValues["WEB_APP_NAME"].Trim()
    }
    else {
        $DefaultWebAppName
    }

    $defaultHostName = az webapp show --resource-group $ResourceGroup --name $webAppName --query defaultHostName --output tsv 2>$null
    Assert-AzSuccess -Message "No se pudo resolver hostname de la Web App '$webAppName'."

    if ([string]::IsNullOrWhiteSpace($defaultHostName)) {
        throw "No se obtuvo hostname válido para la Web App '$webAppName'."
    }

    return "https://$defaultHostName/api/messages"
}

$null = Assert-InfraPrerequisites -ForScript "06-bot-service.ps1"

$resourceGroupName = $script:ResourceGroupName
$defaultWebAppName = if ($script:WebAppName) { $script:WebAppName } else { "wapp-agent-identities-viewer" }
$botServiceName = if ($script:BotServiceName) { $script:BotServiceName } else { "bot-agent-identities-viewer" }

$repoRoot = Get-RepoRoot
$envPath = Join-Path $repoRoot ".env"

$isDeployAllFlow = ($env:RUNNING_FROM_DEPLOY_ALL -eq "1")
if (-not $isDeployAllFlow) {
    Write-Host ""
    Write-Host "[WARN] Ejecución directa detectada para 06-bot-service.ps1." -ForegroundColor Yellow
    Write-Host "[WARN] Antes de continuar, copia .env.generated a .env en la raíz del proyecto." -ForegroundColor Yellow
    Write-Host "[WARN] Cuando termines, confirma para continuar." -ForegroundColor Yellow
    $confirmation = Read-Host "Confirma que ya copiaste .env.generated -> .env (y/Y)"
    if ($confirmation -notin @("y", "Y")) {
        Write-Host "Operación cancelada por el usuario." -ForegroundColor Yellow
        exit 1
    }
}

if (-not (Test-Path $envPath)) {
    Write-Error "No existe .env en la raíz del proyecto: $envPath"
    Write-Host "Genera/completa primero .env (por ejemplo copiando .env.generated a .env) antes de ejecutar este script." -ForegroundColor Yellow
    exit 1
}

$envValues = Parse-DotEnvFile -Path $envPath
$requiredVars = @(
    "MICROSOFT_APP_ID",
    "MICROSOFT_APP_TENANTID"
)

$missing = @()
foreach ($var in $requiredVars) {
    if (-not $envValues.ContainsKey($var) -or [string]::IsNullOrWhiteSpace($envValues[$var])) {
        $missing += $var
    }
}

if ($missing.Count -gt 0) {
    Write-Error "Faltan variables requeridas en .env"
    $missing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    Write-Host "Completa .env antes de ejecutar este script." -ForegroundColor Yellow
    exit 1
}

$appId = $envValues["MICROSOFT_APP_ID"].Trim()
$tenantId = $envValues["MICROSOFT_APP_TENANTID"].Trim()
$appType = "SingleTenant"
$requestedAppType = if ($envValues.ContainsKey("MICROSOFT_APP_TYPE")) { $envValues["MICROSOFT_APP_TYPE"].Trim() } else { "" }
if ($requestedAppType -and $requestedAppType -ne "SingleTenant") {
    Write-Host "[WARN] MICROSOFT_APP_TYPE='$requestedAppType' no es válido para creación actual de Bot Service. Se usará SingleTenant." -ForegroundColor Yellow
}

Write-Step "Verificando Resource Group '$resourceGroupName'..."
$rgExists = az group exists --name $resourceGroupName
Assert-AzSuccess -Message "Error al validar existencia del Resource Group '$resourceGroupName'."
if ($rgExists -eq "false") {
    Write-Error "El Resource Group '$resourceGroupName' no existe"
    Write-Host "Ejecuta primero: .\01-resource-group.ps1" -ForegroundColor Yellow
    exit 1
}
Write-Success "Resource Group validado"

Write-Step "Registrando proveedor Microsoft.BotService (si aplica)..."
Ensure-BotServiceProvider
Write-Success "Proveedor Microsoft.BotService listo"

$agentEndpoint = Resolve-AgentEndpoint -EnvValues $envValues -ResourceGroup $resourceGroupName -DefaultWebAppName $defaultWebAppName
$agentDomain = ([System.Uri]$agentEndpoint).Host

Write-Host "`n$('='*60)" -ForegroundColor Cyan
Write-Host " AZURE BOT SERVICE - CREACIÓN/CONFIGURACIÓN" -ForegroundColor Cyan
Write-Host $('='*60) -ForegroundColor Cyan

Write-Step "Creando/validando Azure Bot Service '$botServiceName'..."
$bot = az bot show --resource-group $resourceGroupName --name $botServiceName --output json 2>$null
if (-not $bot) {
    az bot create `
        --resource-group $resourceGroupName `
        --name $botServiceName `
        --appid $appId `
        --app-type $appType `
        --tenant-id $tenantId `
        --endpoint $agentEndpoint `
        --sku F0 `
        --location global `
        --output none
    Assert-AzSuccess -Message "No se pudo crear Azure Bot Service '$botServiceName'."
    Write-Success "Azure Bot Service creado"
}
else {
    Assert-AzSuccess -Message "Error al consultar Azure Bot Service '$botServiceName'."

    $registeredAppId = az bot show --resource-group $resourceGroupName --name $botServiceName --query properties.msaAppId --output tsv
    Assert-AzSuccess -Message "No se pudo validar AppId de Azure Bot Service '$botServiceName'."

    if (-not [string]::IsNullOrWhiteSpace($registeredAppId) -and $registeredAppId -ne $appId) {
        throw "El bot '$botServiceName' ya existe con otro AppId ($registeredAppId). Revisa o elimina el recurso antes de continuar."
    }

    az bot update `
        --resource-group $resourceGroupName `
        --name $botServiceName `
        --endpoint $agentEndpoint `
        --output none
    Assert-AzSuccess -Message "No se pudo actualizar endpoint del bot '$botServiceName'."
    Write-Success "Azure Bot Service ya existe (endpoint actualizado)"
}

Write-Step "Habilitando canal MsTeamsChannel..."
$teamsChannel = az bot msteams show --resource-group $resourceGroupName --name $botServiceName --output json 2>$null
if (-not $teamsChannel) {
    az bot msteams create --resource-group $resourceGroupName --name $botServiceName --output none
    Assert-AzSuccess -Message "No se pudo habilitar MsTeamsChannel para '$botServiceName'."
    Write-Success "MsTeamsChannel habilitado"
}
else {
    Assert-AzSuccess -Message "Error al consultar MsTeamsChannel para '$botServiceName'."
    Write-Success "MsTeamsChannel ya estaba habilitado"
}

$null = Update-EnvGeneratedSection -ScriptPath $scriptPath -SectionName "06-bot-service.ps1" -SectionValues @{
    BOT_SERVICE_NAME         = $botServiceName
    AGENT_MESSAGES_ENDPOINT  = $agentEndpoint
    AGENT_VALID_DOMAIN       = $agentDomain
}

Write-Host "`n$('-'*60)" -ForegroundColor Gray
Write-Host " ACTUALIZACIÓN DE .env.generated" -ForegroundColor Yellow
Write-Host $('-'*60) -ForegroundColor Gray
Write-Endpoint "BOT_SERVICE_NAME" $botServiceName
Write-Endpoint "AGENT_MESSAGES_ENDPOINT" $agentEndpoint
Write-Endpoint "AGENT_VALID_DOMAIN" $agentDomain

Write-Host "`n$('-'*60)" -ForegroundColor Gray
Write-Host " RESUMEN BOT SERVICE" -ForegroundColor Yellow
Write-Host $('-'*60) -ForegroundColor Gray
Write-Endpoint "ResourceGroup" $resourceGroupName
Write-Endpoint "BotName" $botServiceName
Write-Endpoint "AppId" $appId
Write-Endpoint "AppType" $appType
Write-Endpoint "Endpoint" $agentEndpoint
Write-Endpoint "TeamsChannel" "MsTeamsChannel"
