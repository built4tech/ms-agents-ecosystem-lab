# ============================================================================
# 05-project-crewai.ps1 - Crear proyecto para CrewAI
# ============================================================================

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptPath\..\config\lab-config.ps1"

$projectName = $script:Projects.CrewAI

Write-Host "`n" + "="*60 -ForegroundColor Magenta
Write-Host " PROYECTO: CREWAI" -ForegroundColor Magenta
Write-Host "="*60 -ForegroundColor Magenta

# ----------------------------------------------------------------------------
# 1. Crear Proyecto
# ----------------------------------------------------------------------------
Write-Step "Creando proyecto '$projectName'..."

$projectExists = az ml workspace show `
    --name $projectName `
    --resource-group $script:ResourceGroupName `
    --output json 2>$null

if ($projectExists) {
    Write-Success "Proyecto '$projectName' ya existe"
} else {
    az ml workspace create `
        --kind project `
        --name $projectName `
        --resource-group $script:ResourceGroupName `
        --hub-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$($script:ResourceGroupName)/providers/Microsoft.MachineLearningServices/workspaces/$($script:HubName)" `
        --output none
    
    Write-Success "Proyecto creado"
}

# ----------------------------------------------------------------------------
# 2. Desplegar modelo gpt-4o-mini
# ----------------------------------------------------------------------------
Write-Step "Desplegando modelo $($script:ModelName)..."

$deploymentName = "$($script:ModelName)-deployment"

$deploymentExists = az ml serverless-endpoint show `
    --name $deploymentName `
    --resource-group $script:ResourceGroupName `
    --workspace-name $projectName `
    --output json 2>$null

if ($deploymentExists) {
    Write-Success "Deployment '$deploymentName' ya existe"
} else {
    Write-Info "Creando deployment del modelo (esto puede tardar unos minutos)..."
    
    $deploymentYaml = @"
name: $deploymentName
model_id: azureml://registries/azure-openai/models/$($script:ModelName)/versions/$($script:ModelVersion)
"@
    
    $yamlPath = "$env:TEMP\deployment-crewai.yaml"
    $deploymentYaml | Out-File -FilePath $yamlPath -Encoding utf8
    
    try {
        az ml serverless-endpoint create `
            --file $yamlPath `
            --resource-group $script:ResourceGroupName `
            --workspace-name $projectName `
            --output none
        
        Write-Success "Modelo desplegado exitosamente"
    } catch {
        Write-Info "Nota: Si falla el deployment serverless, puede requerirse creación manual en el portal"
    } finally {
        Remove-Item -Path $yamlPath -Force -ErrorAction SilentlyContinue
    }
}

# ----------------------------------------------------------------------------
# 3. Obtener endpoints
# ----------------------------------------------------------------------------
Write-Host "`n" + "-"*60 -ForegroundColor Gray
Write-Host " CREWAI PROJECT INFO" -ForegroundColor Yellow
Write-Host "-"*60 -ForegroundColor Gray

Write-Endpoint "Project Name" $projectName
Write-Endpoint "Resource Group" $script:ResourceGroupName
Write-Endpoint "Hub" $script:HubName
Write-Endpoint "Location" $script:Location

# Obtener connection string
$subscriptionId = az account show --query id -o tsv
$connectionString = "$($script:Location).api.azureml.ms;$subscriptionId;$($script:ResourceGroupName);$projectName"

Write-Host "`n  CONNECTION STRING (para código):" -ForegroundColor Cyan
Write-Host "  $connectionString" -ForegroundColor White

Write-Host "`n" + "="*60 -ForegroundColor Green
Write-Host " ✓ PROYECTO CREWAI LISTO" -ForegroundColor Green
Write-Host "="*60 -ForegroundColor Green
Write-Host ""
