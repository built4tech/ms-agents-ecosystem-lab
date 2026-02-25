# ============================================================================
# 05-webapp-m365.ps1 - Crear App Service (plan + web app) para runtime M365
# con región independiente del Foundry si se requiere
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
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  1) Crear/reutilizar App Service Plan y Web App              " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  2) Habilitar Managed Identity y asignar rol OpenAI User     " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  3) Aplicar configuración de runtime y app settings          " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  4) Persistir WEB_APP_NAME en .env.generated                 " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
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

function Wait-WebAppReady {
    param(
        [string]$ResourceGroup,
        [string]$WebAppName,
        [int]$MaxAttempts = 24,
        [int]$DelaySeconds = 5
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $name = az webapp show `
            --resource-group $ResourceGroup `
            --name $WebAppName `
            --query name `
            --output tsv 2>$null

        if ($LASTEXITCODE -eq 0 -and $name -eq $WebAppName) {
            return
        }

        Start-Sleep -Seconds $DelaySeconds
    }

    throw "La Web App '$WebAppName' no está disponible tras esperar $(($MaxAttempts * $DelaySeconds)) segundos."
}

function Create-WebAppWithRetry {
    param(
        [string]$ResourceGroup,
        [string]$PlanName,
        [string]$WebAppName,
        [int]$MaxAttempts = 8,
        [int]$DelaySeconds = 15
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $createOutput = az webapp create `
            --resource-group $ResourceGroup `
            --plan $PlanName `
            --name $WebAppName `
            --runtime "PYTHON:3.11" `
            --output none 2>&1 | Out-String

        if ($LASTEXITCODE -eq 0) {
            return
        }

        $isRetryable =
            ($createOutput -match "another operation is in progress") -or
            ($createOutput -match "DeleteServerFarm") -or
            ($createOutput -match "Conflict")

        if (-not $isRetryable -or $attempt -eq $MaxAttempts) {
            throw "No se pudo crear Web App '$WebAppName'. Detalle: $createOutput"
        }

        Write-Host "[INFO] Azure reporta operación en progreso. Reintentando en $DelaySeconds s... (intento $attempt/$MaxAttempts)" -ForegroundColor Gray
        Start-Sleep -Seconds $DelaySeconds
    }
}

function Ensure-WebAppManagedIdentityAndOpenAIRole {
    param(
        [string]$ResourceGroup,
        [string]$WebAppName,
        [string]$FoundryName
    )

    az webapp identity assign `
        --resource-group $ResourceGroup `
        --name $WebAppName `
        --output none
    Assert-AzSuccess -Message "No se pudo habilitar Managed Identity en '$WebAppName'."

    $principalId = az webapp identity show `
        --resource-group $ResourceGroup `
        --name $WebAppName `
        --query principalId `
        --output tsv
    Assert-AzSuccess -Message "No se pudo obtener principalId de la identidad administrada en '$WebAppName'."

    if ([string]::IsNullOrWhiteSpace($principalId)) {
        throw "Managed Identity no devolvió principalId para '$WebAppName'."
    }

    $foundryResourceId = az cognitiveservices account show `
        --resource-group $ResourceGroup `
        --name $FoundryName `
        --query id `
        --output tsv
    Assert-AzSuccess -Message "No se pudo resolver el recurso Foundry '$FoundryName'."

    if ([string]::IsNullOrWhiteSpace($foundryResourceId)) {
        throw "No se obtuvo resource id de Foundry '$FoundryName'."
    }

    $existingRole = az role assignment list `
        --assignee-object-id $principalId `
        --scope $foundryResourceId `
        --role "Cognitive Services OpenAI User" `
        --query "[0].id" `
        --output tsv 2>$null

    if (-not $existingRole) {
        az role assignment create `
            --assignee-object-id $principalId `
            --assignee-principal-type ServicePrincipal `
            --scope $foundryResourceId `
            --role "Cognitive Services OpenAI User" `
            --output none
        Assert-AzSuccess -Message "No se pudo asignar rol 'Cognitive Services OpenAI User' a '$WebAppName'."
        Write-Success "Rol 'Cognitive Services OpenAI User' asignado a la Managed Identity de '$WebAppName'"
    }
    else {
        Write-Success "La Managed Identity de '$WebAppName' ya tiene rol 'Cognitive Services OpenAI User'"
    }
}

$null = Assert-InfraPrerequisites -ForScript "05-webapp-m365.ps1"

$webAppLocation = if ($script:WebAppLocation) { $script:WebAppLocation } else { "spaincentral" }
$webAppName = if ($script:WebAppName) { $script:WebAppName } else { "wapp-agent-identities-viewer" }
$appServicePlanName = if ($script:AppServicePlanName) { $script:AppServicePlanName } else { "asp-agent-identities-viewer" }
$appServicePlanSku = if ($script:AppServicePlanSku) { $script:AppServicePlanSku } else { "B1" }

$repoRoot = Get-RepoRoot
$envPath = Join-Path $repoRoot ".env"
$envGeneratedPath = Join-Path $repoRoot ".env.generated"

$isDeployAllFlow = ($env:RUNNING_FROM_DEPLOY_ALL -eq "1")
if (-not $isDeployAllFlow) {
    Write-Host "" 
    Write-Host "[WARN] Ejecución directa detectada para 05-webapp-m365.ps1." -ForegroundColor Yellow
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
    "ENDPOINT_API",
    "ENDPOINT_OPENAI",
    "DEPLOYMENT_NAME",
    "PROJECT_NAME",
    "API_VERSION",
    "MICROSOFT_APP_ID",
    "MICROSOFT_APP_PASSWORD",
    "MICROSOFT_APP_TYPE",
    "MICROSOFT_APP_TENANTID",
    "APPLICATIONINSIGHTS_CONNECTION_STRING",
    "ENABLE_OBSERVABILITY",
    "ENABLE_A365_OBSERVABILITY_EXPORTER",
    "OTEL_SERVICE_NAME",
    "OTEL_SERVICE_NAMESPACE"
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

Write-Step "Verificando Resource Group '$($script:ResourceGroupName)'..."
$rgExists = az group exists --name $script:ResourceGroupName
Assert-AzSuccess -Message "Error al validar existencia del Resource Group '$($script:ResourceGroupName)'."
if ($rgExists -eq "false") {
    Write-Error "El Resource Group '$($script:ResourceGroupName)' no existe"
    Write-Host "Ejecuta primero: .\01-resource-group.ps1" -ForegroundColor Yellow
    exit 1
}
Write-Success "Resource Group validado"

Write-Host "`n$('='*60)" -ForegroundColor Cyan
Write-Host " APP SERVICE M365 - CREACIÓN/CONFIGURACIÓN" -ForegroundColor Cyan
Write-Host $('='*60) -ForegroundColor Cyan

Write-Step "Creando/validando App Service Plan '$appServicePlanName' ($webAppLocation)..."
$planExists = az appservice plan show --resource-group $script:ResourceGroupName --name $appServicePlanName --output json 2>$null
if (-not $planExists) {
    az appservice plan create `
        --resource-group $script:ResourceGroupName `
        --name $appServicePlanName `
        --is-linux `
        --location $webAppLocation `
        --sku $appServicePlanSku `
        --output none
    Assert-AzSuccess -Message "No se pudo crear App Service Plan '$appServicePlanName'."
    Write-Success "App Service Plan creado"
} else {
    Assert-AzSuccess -Message "Error al consultar App Service Plan '$appServicePlanName'."
    Write-Success "App Service Plan ya existe"
}

Write-Step "Creando/validando Web App '$webAppName'..."
$webAppExists = az webapp show --resource-group $script:ResourceGroupName --name $webAppName --output json 2>$null
if (-not $webAppExists) {
    Create-WebAppWithRetry `
        -ResourceGroup $script:ResourceGroupName `
        -PlanName $appServicePlanName `
        -WebAppName $webAppName
    Write-Success "Web App creada"
} else {
    Assert-AzSuccess -Message "Error al consultar Web App '$webAppName'."
    Write-Success "Web App ya existe"
}

Write-Step "Esperando disponibilidad de Web App '$webAppName'..."
Wait-WebAppReady -ResourceGroup $script:ResourceGroupName -WebAppName $webAppName
Write-Success "Web App disponible"

Write-Step "Habilitando Managed Identity y acceso a Foundry/OpenAI..."
Ensure-WebAppManagedIdentityAndOpenAIRole `
    -ResourceGroup $script:ResourceGroupName `
    -WebAppName $webAppName `
    -FoundryName $script:FoundryName

Write-Step "Aplicando configuración de runtime para M365..."

$settingsList = @(
    "SCM_DO_BUILD_DURING_DEPLOYMENT=true",
    "ENABLE_ORYX_BUILD=true",
    "AGENT_HOST=0.0.0.0",
    "PORT=8000"
)

foreach ($key in $requiredVars) {
    $settingsList += "$key=$($envValues[$key])"
}

az webapp config appsettings set `
    --resource-group $script:ResourceGroupName `
    --name $webAppName `
    --settings $settingsList `
    --output none
Assert-AzSuccess -Message "No se pudieron aplicar App Settings en '$webAppName'."

az webapp config set `
    --resource-group $script:ResourceGroupName `
    --name $webAppName `
    --startup-file "python main.py" `
    --output none
Assert-AzSuccess -Message "No se pudo configurar runtime/startup en '$webAppName'."
Write-Success "Configuración de runtime aplicada"

$defaultHostName = az webapp show --resource-group $script:ResourceGroupName --name $webAppName --query defaultHostName --output tsv
Assert-AzSuccess -Message "No se pudo obtener el hostname de '$webAppName'."
$webAppUrl = "https://$defaultHostName/api/messages"

$null = Update-EnvGeneratedSection -ScriptPath $scriptPath -SectionName "05-webapp-m365.ps1" -SectionValues @{
    WEB_APP_NAME = $webAppName
}

Write-Host "`n$('-'*60)" -ForegroundColor Gray
Write-Host " ACTUALIZACIÓN DE .env.generated" -ForegroundColor Yellow
Write-Host $('-'*60) -ForegroundColor Gray
Write-Endpoint "WEB_APP_NAME" $webAppName