# ============================================================================
# 02-ai-hub.ps1 - Crear AI Foundry Hub y recursos dependientes
# ============================================================================

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptPath\..\config\lab-config.ps1"

Write-Host "`n" + "="*60 -ForegroundColor Magenta
Write-Host " CREACIÓN DE AI FOUNDRY HUB" -ForegroundColor Magenta
Write-Host "="*60 -ForegroundColor Magenta

# ----------------------------------------------------------------------------
# 1. Log Analytics Workspace (requerido por Application Insights)
# ----------------------------------------------------------------------------
Write-Step "Creando Log Analytics Workspace..."

$logExists = az monitor log-analytics workspace show `
    --resource-group $script:ResourceGroupName `
    --workspace-name $script:LogAnalyticsName `
    --output json 2>$null

if ($logExists) {
    Write-Success "Log Analytics '$($script:LogAnalyticsName)' ya existe"
} else {
    az monitor log-analytics workspace create `
        --resource-group $script:ResourceGroupName `
        --workspace-name $script:LogAnalyticsName `
        --location $script:Location `
        --output none
    
    Write-Success "Log Analytics creado"
}

$logWorkspace = az monitor log-analytics workspace show `
    --resource-group $script:ResourceGroupName `
    --workspace-name $script:LogAnalyticsName `
    --output json | ConvertFrom-Json

# ----------------------------------------------------------------------------
# 2. Application Insights
# ----------------------------------------------------------------------------
Write-Step "Creando Application Insights..."

$appInsightsExists = az monitor app-insights component show `
    --app $script:AppInsightsName `
    --resource-group $script:ResourceGroupName `
    --output json 2>$null

if ($appInsightsExists) {
    Write-Success "Application Insights '$($script:AppInsightsName)' ya existe"
} else {
    az monitor app-insights component create `
        --app $script:AppInsightsName `
        --resource-group $script:ResourceGroupName `
        --location $script:Location `
        --workspace $logWorkspace.id `
        --output none
    
    Write-Success "Application Insights creado"
}

$appInsights = az monitor app-insights component show `
    --app $script:AppInsightsName `
    --resource-group $script:ResourceGroupName `
    --output json | ConvertFrom-Json

# ----------------------------------------------------------------------------
# 3. Storage Account
# ----------------------------------------------------------------------------
Write-Step "Creando Storage Account..."

# Buscar si ya existe un storage account con el patrón
$existingStorage = az storage account list `
    --resource-group $script:ResourceGroupName `
    --query "[?starts_with(name, 'stagentslab')].name" `
    --output tsv

if ($existingStorage) {
    $script:StorageAccountName = $existingStorage
    Write-Success "Storage Account '$($script:StorageAccountName)' ya existe"
} else {
    # Generar nombre único
    $script:StorageAccountName = "stagentslab$(Get-Random -Minimum 10000 -Maximum 99999)"
    
    az storage account create `
        --name $script:StorageAccountName `
        --resource-group $script:ResourceGroupName `
        --location $script:Location `
        --sku Standard_LRS `
        --output none
    
    Write-Success "Storage Account '$($script:StorageAccountName)' creado"
}

$storageAccount = az storage account show `
    --name $script:StorageAccountName `
    --resource-group $script:ResourceGroupName `
    --output json | ConvertFrom-Json

# ----------------------------------------------------------------------------
# 4. Key Vault
# ----------------------------------------------------------------------------
Write-Step "Creando Key Vault..."

# Buscar si ya existe un key vault con el patrón
$existingKv = az keyvault list `
    --resource-group $script:ResourceGroupName `
    --query "[?starts_with(name, 'kv-agents-lab')].name" `
    --output tsv

if ($existingKv) {
    $script:KeyVaultName = $existingKv
    Write-Success "Key Vault '$($script:KeyVaultName)' ya existe"
} else {
    # Generar nombre único
    $script:KeyVaultName = "kv-agents-lab-$(Get-Random -Minimum 10000 -Maximum 99999)"
    
    az keyvault create `
        --name $script:KeyVaultName `
        --resource-group $script:ResourceGroupName `
        --location $script:Location `
        --output none
    
    Write-Success "Key Vault '$($script:KeyVaultName)' creado"
}

$keyVault = az keyvault show `
    --name $script:KeyVaultName `
    --resource-group $script:ResourceGroupName `
    --output json | ConvertFrom-Json

# ----------------------------------------------------------------------------
# 5. AI Foundry Hub
# ----------------------------------------------------------------------------
Write-Step "Creando AI Foundry Hub..."

$hubExists = az ml workspace show `
    --name $script:HubName `
    --resource-group $script:ResourceGroupName `
    --output json 2>$null

if ($hubExists) {
    Write-Success "AI Hub '$($script:HubName)' ya existe"
} else {
    az ml workspace create `
        --kind hub `
        --name $script:HubName `
        --resource-group $script:ResourceGroupName `
        --location $script:Location `
        --storage-account $storageAccount.id `
        --key-vault $keyVault.id `
        --application-insights $appInsights.id `
        --output none
    
    Write-Success "AI Hub creado"
}

# Mostrar información del Hub
Write-Host "`n" + "-"*60 -ForegroundColor Gray
Write-Host " AI FOUNDRY HUB INFO" -ForegroundColor Yellow
Write-Host "-"*60 -ForegroundColor Gray

$hubInfo = az ml workspace show `
    --name $script:HubName `
    --resource-group $script:ResourceGroupName `
    --output json | ConvertFrom-Json

Write-Endpoint "Hub Name" $hubInfo.name
Write-Endpoint "Location" $hubInfo.location
Write-Endpoint "Storage" $script:StorageAccountName
Write-Endpoint "Key Vault" $script:KeyVaultName
Write-Endpoint "App Insights" $script:AppInsightsName

Write-Host "`n" + "="*60 -ForegroundColor Green
Write-Host " ✓ AI FOUNDRY HUB LISTO" -ForegroundColor Green
Write-Host "="*60 -ForegroundColor Green
Write-Host ""
