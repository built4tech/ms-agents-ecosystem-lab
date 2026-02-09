# ============================================================================
# 05-project-crewai.ps1 - Crear proyecto para CrewAI
# ============================================================================

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptPath\..\config\lab-config.ps1"

$projectName = $script:Projects.CrewAI

Write-Host "`n$("="*60)" -ForegroundColor Magenta
Write-Host " PROYECTO: CREWAI" -ForegroundColor Magenta
Write-Host $("="*60) -ForegroundColor Magenta

# ----------------------------------------------------------------------------
# 1. Crear Proyecto (hereda conexiones del Hub)
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
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Proyecto creado"
    } else {
        Write-Error "Error al crear el proyecto"
    }
}

# ----------------------------------------------------------------------------
# 1.5. Asignar rol RBAC al Proyecto para acceso AAD a Azure OpenAI
# ----------------------------------------------------------------------------
Write-Step "Asignando permisos RBAC al proyecto sobre Azure OpenAI..."

# Obtener el principal ID (managed identity) del proyecto
$projectPrincipalId = az ml workspace show `
    --name $projectName `
    --resource-group $script:ResourceGroupName `
    --query "identity.principal_id" -o tsv

# Obtener el nombre del recurso Azure OpenAI (buscar el que existe en el RG)
$aoaiName = az cognitiveservices account list `
    --resource-group $script:ResourceGroupName `
    --query "[?kind=='OpenAI'].name" -o tsv

if ($projectPrincipalId -and $aoaiName) {
    $aoaiResourceId = az cognitiveservices account show `
        --name $aoaiName `
        --resource-group $script:ResourceGroupName `
        --query "id" -o tsv
    
    # Verificar si el rol ya esta asignado
    $existingRole = az role assignment list `
        --assignee $projectPrincipalId `
        --scope $aoaiResourceId `
        --role "Azure AI Developer" `
        --query "[0].id" -o tsv 2>$null
    
    if ($existingRole) {
        Write-Success "Rol RBAC ya asignado al proyecto"
    } else {
        az role assignment create `
            --assignee $projectPrincipalId `
            --role "Azure AI Developer" `
            --scope $aoaiResourceId `
            --output none
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Rol 'Azure AI Developer' asignado al proyecto"
        } else {
            Write-Warning "No se pudo asignar rol RBAC (puede requerir permisos de Owner)"
        }
    }
} else {
    Write-Warning "No se pudo obtener la managed identity del proyecto o el recurso Azure OpenAI"
}

# ----------------------------------------------------------------------------
# 2. Mostrar informacion del proyecto
# ----------------------------------------------------------------------------
Write-Host "`n$("-"*60)" -ForegroundColor Gray
Write-Host " CREWAI PROJECT INFO" -ForegroundColor Yellow
Write-Host $("-"*60) -ForegroundColor Gray

Write-Endpoint "Project Name" $projectName
Write-Endpoint "Resource Group" $script:ResourceGroupName
Write-Endpoint "Hub" $script:HubName
Write-Endpoint "Location" $script:Location

# Endpoint del Azure OpenAI compartido (configurado en el Hub)
$aoaiEndpoint = "https://$($script:AzureOpenAIName).openai.azure.com"

Write-Host "`n  AZURE OPENAI (heredado del Hub):" -ForegroundColor Cyan
Write-Host "  Endpoint: $aoaiEndpoint" -ForegroundColor White
Write-Host "  Deployment: $($script:ModelName)" -ForegroundColor White
Write-Host "  Conexion: aoai-connection" -ForegroundColor White

Write-Host "`n  USO EN CODIGO (CrewAI):" -ForegroundColor Cyan
Write-Host "  from crewai import Agent, LLM" -ForegroundColor Gray
Write-Host "" -ForegroundColor Gray
Write-Host "  llm = LLM(" -ForegroundColor Gray
Write-Host "      model='azure/$($script:ModelName)'," -ForegroundColor Gray
Write-Host "      api_base='$aoaiEndpoint'," -ForegroundColor Gray
Write-Host "      api_version='2024-02-15-preview'" -ForegroundColor Gray
Write-Host "  )" -ForegroundColor Gray
Write-Host "" -ForegroundColor Gray
Write-Host "  agent = Agent(" -ForegroundColor Gray
Write-Host "      role='Investigador'," -ForegroundColor Gray
Write-Host "      goal='Investigar temas'," -ForegroundColor Gray
Write-Host "      llm=llm" -ForegroundColor Gray
Write-Host "  )" -ForegroundColor Gray

Write-Host "`n$("="*60)" -ForegroundColor Green
Write-Host " PROYECTO CREWAI LISTO" -ForegroundColor Green
Write-Host $("="*60) -ForegroundColor Green
Write-Host ""
