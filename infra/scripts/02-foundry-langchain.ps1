# ============================================================================
# 02-foundry-langchain.ps1 - Crear recurso Foundry (AIServices) + despliegue gpt-4o-mini
# ============================================================================

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptPath\..\config\lab-config.ps1"

$framework = "LangChain"
$hubConfig = $script:Projects[$framework]

Write-Host "`n$("="*60)" -ForegroundColor Cyan
Write-Host " Proyecto $framework - CREACIÓN" -ForegroundColor Cyan
Write-Host $("="*60) -ForegroundColor Cyan

# Verificar Resource Group
$rgExists = az group exists --name $script:ResourceGroupName
if ($rgExists -eq "false") {
    Write-Error "El Resource Group '$($script:ResourceGroupName)' no existe"
    Write-Host "Ejecuta primero: .\01-resource-group.ps1" -ForegroundColor Yellow
    exit 1
}

# Obtener cuenta para usar subscription en llamadas REST
$account = az account show --output json | ConvertFrom-Json

# ============================================================================
# 1. Recurso Foundry (AIServices)
# ============================================================================
$foundryName = $hubConfig.FoundryName
$accountBaseUrl = "https://management.azure.com/subscriptions/$($account.id)/resourceGroups/$($script:ResourceGroupName)/providers/Microsoft.CognitiveServices/accounts/$foundryName"

Write-Step "Creando recurso Foundry (AIServices) '$foundryName'..."

$foundryExists = az cognitiveservices account show `
    --name $foundryName `
    --resource-group $script:ResourceGroupName `
    --output json 2>$null

if ($foundryExists) {
    Write-Success "Foundry '$foundryName' ya existe"
} else {
    az cognitiveservices account create `
        --name $foundryName `
        --resource-group $script:ResourceGroupName `
        --kind "AIServices" `
        --sku "S0" `
        --location $script:Location `
        --custom-domain $foundryName `
        --assign-identity `
        --output none

    Write-Success "Recurso Foundry creado"
}

# Habilitar gestión de proyectos (requerido para crear projects en el portal)
$allowProjectManagement = $false
try {
    $allowProjectManagement = az rest `
        --method get `
        --url $accountBaseUrl `
        --url-parameters api-version=2025-06-01 `
        --query "properties.allowProjectManagement" `
        --output tsv 2>$null
} catch {
    $allowProjectManagement = $false
}

if ($allowProjectManagement -ne $true) {
    Write-Step "Habilitando allowProjectManagement en '$foundryName'..."
    $accountPatch = @{ properties = @{ allowProjectManagement = $true } } | ConvertTo-Json -Compress
    $accountPatchFile = New-TemporaryFile
    Set-Content -Path $accountPatchFile -Value $accountPatch -Encoding utf8

    try {
        az rest `
            --method patch `
            --url $accountBaseUrl `
            --url-parameters api-version=2025-06-01 `
            --headers "Content-Type=application/json" `
            --body @$accountPatchFile `
            --output none | Out-Null
        Write-Success "allowProjectManagement habilitado"
    } catch {
        Write-Error "No se pudo habilitar allowProjectManagement ($($_.Exception.Message))"
        throw
    } finally {
        Remove-Item -Path $accountPatchFile -ErrorAction SilentlyContinue
    }
} else {
    Write-Success "allowProjectManagement ya está habilitado"
}

$foundryInfo = az cognitiveservices account show `
    --name $foundryName `
    --resource-group $script:ResourceGroupName `
    --output json | ConvertFrom-Json

Write-Host "`n$('-'*60)" -ForegroundColor Gray
Write-Host " FOUNDRY INFO" -ForegroundColor Yellow
Write-Host $('-'*60) -ForegroundColor Gray
Write-Endpoint "Nombre" $foundryInfo.name
Write-Endpoint "Location" $foundryInfo.location
Write-Endpoint "Endpoint API" "https://$($foundryInfo.name).services.ai.azure.com/"
Write-Endpoint "Endpoint OpenAI" "https://$($foundryInfo.name).openai.azure.com/"

# ============================================================================
# ============================================================================
# 2. Proyecto para agentes (projects)
#    Necesario para usar la vista Project y Agents en el portal
# ============================================================================
$projectName = "$foundryName-project"
$projectApiVersion = "2025-06-01"
$projectBaseUrl = "$accountBaseUrl/projects/$projectName"

Write-Step "Creando proyecto de agentes '$projectName' en $foundryName..."

$projectExists = $null
try {
    $projectExists = az rest `
        --method get `
        --url $projectBaseUrl `
        --url-parameters api-version=$projectApiVersion `
        --output json 2>$null
} catch {
    $projectExists = $null
}

if ($projectExists) {
    Write-Success "Proyecto '$projectName' ya existe"
} else {
    $projectBody = @{ location = $script:Location; identity = @{ type = "SystemAssigned" }; properties = @{} } | ConvertTo-Json -Compress
    $projectBodyFile = New-TemporaryFile
    Set-Content -Path $projectBodyFile -Value $projectBody -Encoding utf8

    try {
        az rest `
            --method put `
            --url $projectBaseUrl `
            --url-parameters api-version=$projectApiVersion `
            --headers "Content-Type=application/json" `
            --body @$projectBodyFile `
            --output none | Out-Null
        Write-Success "Proyecto de agentes creado"
    } catch {
        Write-Error "No se pudo crear el proyecto de agentes ($($_.Exception.Message))"
        throw
    } finally {
        Remove-Item -Path $projectBodyFile -ErrorAction SilentlyContinue
    }
}

Write-Host "`n$('-'*60)" -ForegroundColor Gray
Write-Host " AGENTS PROJECT" -ForegroundColor Yellow
Write-Host $('-'*60) -ForegroundColor Gray
Write-Endpoint "Project" $projectName
Write-Endpoint "API Version" $projectApiVersion

# ============================================================================
# 3. Desplegar modelo gpt-4o-mini en Foundry
# ============================================================================
Write-Step "Desplegando modelo $($script:ModelName) en $foundryName..."

$deploymentName = $script:ModelName

$deploymentExists = az cognitiveservices account deployment show `
    --name $foundryName `
    --resource-group $script:ResourceGroupName `
    --deployment-name $deploymentName `
    --output json 2>$null

if ($deploymentExists) {
    Write-Success "Deployment '$deploymentName' ya existe"
} else {
    az cognitiveservices account deployment create `
        --name $foundryName `
        --resource-group $script:ResourceGroupName `
        --deployment-name $deploymentName `
        --model-name $script:ModelName `
        --model-version $script:ModelVersion `
        --model-format "OpenAI" `
        --sku-capacity $script:ModelCapacity `
        --sku-name $script:ModelSku `
        --output none

    Write-Success "Modelo desplegado exitosamente"
}

Write-Host "`n$('-'*60)" -ForegroundColor Gray
Write-Host " DEPLOYMENT INFO" -ForegroundColor Yellow
Write-Host $('-'*60) -ForegroundColor Gray
Write-Endpoint "Deployment" $deploymentName
Write-Endpoint "Modelo" $script:ModelName
Write-Endpoint "Version" $script:ModelVersion
Write-Endpoint "Endpoint OpenAI" "https://$($foundryInfo.name).openai.azure.com/"

Write-Host "`n$('='*60)" -ForegroundColor Green
Write-Host " FOUNDRY $framework LISTO" -ForegroundColor Green
Write-Host $('='*60) -ForegroundColor Green
Write-Host ""
