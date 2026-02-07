# ============================================================================
# show-endpoints.ps1 - Mostrar endpoints y generar archivo .env
# ============================================================================

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptPath\..\config\lab-config.ps1"

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                                                              ║" -ForegroundColor Cyan
Write-Host "║          MS AGENTS ECOSYSTEM LAB - ENDPOINTS                ║" -ForegroundColor Cyan
Write-Host "║                                                              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Verificar autenticación
$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "  No hay sesión activa. Ejecuta 'az login' primero." -ForegroundColor Red
    exit 1
}

$subscriptionId = $account.id

# Verificar que el RG existe
$rgExists = az group exists --name $script:ResourceGroupName
if ($rgExists -eq "false") {
    Write-Host "  El Resource Group '$($script:ResourceGroupName)' no existe." -ForegroundColor Red
    Write-Host "  Ejecuta 'deploy-all.ps1' para crear la infraestructura." -ForegroundColor Yellow
    exit 1
}

Write-Host "┌──────────────────────────────────────────────────────────────┐" -ForegroundColor Gray
Write-Host "│ INFORMACIÓN GENERAL                                          │" -ForegroundColor Gray
Write-Host "└──────────────────────────────────────────────────────────────┘" -ForegroundColor Gray
Write-Host ""
Write-Endpoint "Subscription ID" $subscriptionId
Write-Endpoint "Resource Group" $script:ResourceGroupName
Write-Endpoint "Location" $script:Location
Write-Endpoint "AI Hub" $script:HubName

# ----------------------------------------------------------------------------
# Generar contenido del archivo .env
# ----------------------------------------------------------------------------

$envContent = @"
# ============================================================================
# Variables de entorno generadas automáticamente
# Generado: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# ============================================================================

# Configuración común de Azure
AZURE_SUBSCRIPTION_ID=$subscriptionId
AZURE_RESOURCE_GROUP=$($script:ResourceGroupName)
AZURE_LOCATION=$($script:Location)

"@

$deploymentName = "$($script:ModelName)-deployment"

# ----------------------------------------------------------------------------
# Procesar cada proyecto
# ----------------------------------------------------------------------------

foreach ($project in $script:Projects.GetEnumerator()) {
    $framework = $project.Key
    $projectName = $project.Value
    $prefix = $framework.ToUpper()
    
    Write-Host ""
    Write-Host "┌──────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host "│ $($framework.ToUpper().PadRight(60)) │" -ForegroundColor Yellow
    Write-Host "└──────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
    Write-Host ""
    
    # Verificar si el proyecto existe
    $projectExists = az ml workspace show `
        --name $projectName `
        --resource-group $script:ResourceGroupName `
        --output json 2>$null
    
    if (-not $projectExists) {
        Write-Host "  ⚠️  Proyecto no encontrado" -ForegroundColor Red
        continue
    }
    
    Write-Endpoint "Project Name" $projectName
    Write-Endpoint "Deployment" $deploymentName
    
    if ($framework -eq "CrewAI") {
        # CrewAI usa endpoint OpenAI-compatible con DefaultAzureCredential
        $endpoint = "https://$projectName.openai.azure.com"
        Write-Endpoint "Endpoint (OpenAI)" $endpoint
        
        Write-Host ""
        Write-Host "  Nota: Usa DefaultAzureCredential para autenticación" -ForegroundColor Gray
        
        $envContent += @"
# $framework (endpoint OpenAI-compatible con DefaultAzureCredential)
${prefix}_ENDPOINT=$endpoint
${prefix}_DEPLOYMENT_NAME=$deploymentName

"@
    } else {
        # Foundry y MAF usan endpoint de AI Services
        $endpoint = "https://$projectName.services.ai.azure.com"
        Write-Endpoint "Endpoint (AI Services)" $endpoint
        
        $envContent += @"
# $framework (endpoint Azure AI Services)
${prefix}_ENDPOINT=$endpoint
${prefix}_PROJECT_NAME=$projectName
${prefix}_DEPLOYMENT_NAME=$deploymentName

"@
    }
}

# ----------------------------------------------------------------------------
# Mostrar preview del archivo .env
# ----------------------------------------------------------------------------

Write-Host ""
Write-Host "┌──────────────────────────────────────────────────────────────┐" -ForegroundColor Green
Write-Host "│ CONTENIDO DE .env.generated                                  │" -ForegroundColor Green
Write-Host "└──────────────────────────────────────────────────────────────┘" -ForegroundColor Green
Write-Host ""
Write-Host $envContent -ForegroundColor Gray

# ----------------------------------------------------------------------------
# Guardar archivo .env.generated
# ----------------------------------------------------------------------------

Write-Host ""
$saveEnv = Read-Host "  ¿Guardar como .env.generated en la raíz del proyecto? (s/N)"

if ($saveEnv -eq "s" -or $saveEnv -eq "S") {
    $envPath = Join-Path (Split-Path -Parent (Split-Path -Parent $scriptPath)) ".env.generated"
    $envContent | Out-File -FilePath $envPath -Encoding utf8
    Write-Host ""
    Write-Host "  ✓ Archivo guardado en: $envPath" -ForegroundColor Green
    Write-Host "  Copia las variables necesarias a tu archivo .env" -ForegroundColor Gray
}

Write-Host ""
