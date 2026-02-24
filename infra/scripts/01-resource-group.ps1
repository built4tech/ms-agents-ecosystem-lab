# ============================================================================
# 01-resource-group.ps1 - Crear Resource Group
# ============================================================================

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptPath\..\config\lab-config.ps1"
. "$scriptPath\env-generated-helper.ps1"

Write-Host "`n$("="*60)" -ForegroundColor Magenta
Write-Host " CREACIÓN DE RESOURCE GROUP" -ForegroundColor Magenta
Write-Host $("="*60) -ForegroundColor Magenta

# Verificar si el RG ya existe
Write-Step "Verificando si el Resource Group existe..."
$rgExists = az group exists --name $script:ResourceGroupName

if ($rgExists -eq "true") {
    Write-Success "Resource Group '$($script:ResourceGroupName)' ya existe"
} else {
    Write-Step "Creando Resource Group '$($script:ResourceGroupName)'..."
    
    $tagsString = Get-TagsString
    
    az group create `
        --name $script:ResourceGroupName `
        --location $script:Location `
        --tags $tagsString.Split(" ") `
        --output none
    
    Write-Success "Resource Group creado exitosamente"
}

# Mostrar información del RG
Write-Host "`n$("-"*60)" -ForegroundColor Gray
Write-Host " RESOURCE GROUP INFO" -ForegroundColor Yellow
Write-Host $("-"*60) -ForegroundColor Gray

$rgInfo = az group show --name $script:ResourceGroupName --output json | ConvertFrom-Json
$account = az account show --output json | ConvertFrom-Json

$envPath = Update-EnvGeneratedSection -ScriptPath $scriptPath -SectionName "01-resource-group.ps1" -SectionValues @{
    AZURE_SUBSCRIPTION_ID = $account.id
    AZURE_RESOURCE_GROUP  = $script:ResourceGroupName
    AZURE_LOCATION        = $script:Location
}

Write-Endpoint "Nombre" $rgInfo.name
Write-Endpoint "Ubicación" $rgInfo.location
Write-Endpoint "ID" $rgInfo.id
Write-Endpoint ".env.generated" $envPath

Write-Host "`n$("="*60)" -ForegroundColor Green
Write-Host " RESOURCE GROUP LISTO" -ForegroundColor Green
Write-Host $("="*60) -ForegroundColor Green
Write-Host ""
