# ============================================================================
# 04-project-maf.ps1 - Crear proyecto para Microsoft Agent Framework
# ============================================================================

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptPath\..\config\lab-config.ps1"

$projectName = $script:Projects.MAF

Write-Host "`n$("="*60)" -ForegroundColor Magenta
Write-Host " PROYECTO: MICROSOFT AGENT FRAMEWORK" -ForegroundColor Magenta
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
# 2. Mostrar informacion del proyecto
# ----------------------------------------------------------------------------
Write-Host "`n$("-"*60)" -ForegroundColor Gray
Write-Host " MAF PROJECT INFO" -ForegroundColor Yellow
Write-Host $("-"*60) -ForegroundColor Gray

Write-Endpoint "Project Name" $projectName
Write-Endpoint "Resource Group" $script:ResourceGroupName
Write-Endpoint "Hub" $script:HubName
Write-Endpoint "Location" $script:Location

# Obtener el endpoint del proyecto para MAF
$subscriptionId = az account show --query id -o tsv
$projectEndpoint = "https://$projectName.services.ai.azure.com"

Write-Host "`n  AZURE OPENAI (heredado del Hub):" -ForegroundColor Cyan
Write-Host "  Recurso: $($script:AzureOpenAIName)" -ForegroundColor White
Write-Host "  Deployment: $($script:ModelName)" -ForegroundColor White
Write-Host "  Conexion: aoai-connection" -ForegroundColor White

Write-Host "`n  USO EN CODIGO (MAF/AutoGen):" -ForegroundColor Cyan
Write-Host "  from azure.ai.projects import AIProjectClient" -ForegroundColor Gray
Write-Host "  from azure.identity import DefaultAzureCredential" -ForegroundColor Gray
Write-Host "" -ForegroundColor Gray
Write-Host "  project = AIProjectClient(" -ForegroundColor Gray
Write-Host "      credential=DefaultAzureCredential()," -ForegroundColor Gray
Write-Host "      endpoint='$projectEndpoint'" -ForegroundColor Gray
Write-Host "  )" -ForegroundColor Gray
Write-Host "" -ForegroundColor Gray
Write-Host "  # Crear agente (aparecera en el portal de AI Foundry)" -ForegroundColor Gray
Write-Host "  agent = project.agents.create_agent(" -ForegroundColor Gray
Write-Host "      model='$($script:ModelName)'," -ForegroundColor Gray
Write-Host "      name='mi-agente'" -ForegroundColor Gray
Write-Host "  )" -ForegroundColor Gray

Write-Host "`n$("="*60)" -ForegroundColor Green
Write-Host " PROYECTO MAF LISTO" -ForegroundColor Green
Write-Host $("="*60) -ForegroundColor Green
Write-Host ""
