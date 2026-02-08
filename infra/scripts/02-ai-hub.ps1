# ============================================================================
# 02-ai-hub.ps1 - Crear AI Foundry Hub y recursos dependientes
# ============================================================================

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptPath\..\config\lab-config.ps1"

Write-Host "`n$("="*60)" -ForegroundColor Magenta
Write-Host " CREACIÓN DE AI FOUNDRY HUB" -ForegroundColor Magenta
Write-Host $("="*60) -ForegroundColor Magenta

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
        --public-network-access Enabled `
        --output none
    
    Write-Success "AI Hub creado"
}

# Mostrar información del Hub
Write-Host "`n$("-"*60)" -ForegroundColor Gray
Write-Host " AI FOUNDRY HUB INFO" -ForegroundColor Yellow
Write-Host $("-"*60) -ForegroundColor Gray

$hubInfo = az ml workspace show `
    --name $script:HubName `
    --resource-group $script:ResourceGroupName `
    --output json | ConvertFrom-Json

Write-Endpoint "Hub Name" $hubInfo.name
Write-Endpoint "Location" $hubInfo.location
Write-Endpoint "Storage" $script:StorageAccountName
Write-Endpoint "Key Vault" $script:KeyVaultName
Write-Endpoint "App Insights" $script:AppInsightsName

# ----------------------------------------------------------------------------
# 6. Azure OpenAI (recurso compartido)
# ----------------------------------------------------------------------------
$aoaiName = $script:AzureOpenAIName

Write-Step "Creando recurso Azure OpenAI '$aoaiName'..."

$aoaiExists = az cognitiveservices account show `
    --name $aoaiName `
    --resource-group $script:ResourceGroupName `
    --output json 2>$null

if ($aoaiExists) {
    Write-Success "Recurso Azure OpenAI '$aoaiName' ya existe"
} else {
    az cognitiveservices account create `
        --name $aoaiName `
        --resource-group $script:ResourceGroupName `
        --kind "OpenAI" `
        --sku "S0" `
        --location $script:Location `
        --custom-domain $aoaiName `
        --output none
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Recurso Azure OpenAI creado"
    } else {
        Write-Error "Error al crear recurso Azure OpenAI"
    }
}

# ----------------------------------------------------------------------------
# 7. Desplegar modelo gpt-4o-mini
# ----------------------------------------------------------------------------
Write-Step "Desplegando modelo $($script:ModelName)..."

$deploymentName = $script:ModelName

$deploymentExists = az cognitiveservices account deployment show `
    --name $aoaiName `
    --resource-group $script:ResourceGroupName `
    --deployment-name $deploymentName `
    --output json 2>$null

if ($deploymentExists) {
    Write-Success "Deployment '$deploymentName' ya existe"
} else {
    Write-Info "Creando deployment del modelo..."
    
    az cognitiveservices account deployment create `
        --name $aoaiName `
        --resource-group $script:ResourceGroupName `
        --deployment-name $deploymentName `
        --model-name $script:ModelName `
        --model-version $script:ModelVersion `
        --model-format "OpenAI" `
        --sku-capacity $script:ModelCapacity `
        --sku-name $script:ModelSku `
        --output none
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Modelo desplegado exitosamente"
    } else {
        Write-Error "Error al desplegar el modelo"
    }
}

# ----------------------------------------------------------------------------
# 8. Crear conexion del Hub a Azure OpenAI
# ----------------------------------------------------------------------------
Write-Step "Creando conexion del Hub a Azure OpenAI..."

$connectionName = "aoai-connection"

# Obtener el endpoint y la key del recurso Azure OpenAI
$aoaiEndpoint = "https://$aoaiName.openai.azure.com/"
$aoaiKey = az cognitiveservices account keys list `
    --name $aoaiName `
    --resource-group $script:ResourceGroupName `
    --query "key1" -o tsv

# Verificar si la conexion ya existe
$connectionExists = az ml connection show `
    --name $connectionName `
    --resource-group $script:ResourceGroupName `
    --workspace-name $script:HubName `
    --output json 2>$null

if ($connectionExists) {
    Write-Success "Conexion '$connectionName' ya existe"
} else {
    # Crear archivo YAML para la conexion
    $connectionYaml = @"
name: $connectionName
type: azure_open_ai
azure_endpoint: $aoaiEndpoint
api_key: $aoaiKey
"@
    
    $yamlPath = "$env:TEMP\connection-aoai.yaml"
    $connectionYaml | Out-File -FilePath $yamlPath -Encoding utf8
    
    az ml connection create `
        --file $yamlPath `
        --resource-group $script:ResourceGroupName `
        --workspace-name $script:HubName `
        --output none
    
    Remove-Item -Path $yamlPath -Force -ErrorAction SilentlyContinue
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Conexion creada exitosamente"
    } else {
        Write-Error "Error al crear la conexion"
        Write-Info "Puede crearse manualmente desde el portal de AI Foundry"
    }
}

# Mostrar información de Azure OpenAI
Write-Host "`n$("-"*60)" -ForegroundColor Gray
Write-Host " AZURE OPENAI INFO" -ForegroundColor Yellow
Write-Host $("-"*60) -ForegroundColor Gray

Write-Endpoint "Recurso" $aoaiName
Write-Endpoint "Endpoint" $aoaiEndpoint
Write-Endpoint "Modelo" $deploymentName
Write-Endpoint "Conexion Hub" $connectionName

Write-Host "`n$("="*60)" -ForegroundColor Green
Write-Host " AI FOUNDRY HUB LISTO" -ForegroundColor Green
Write-Host $("="*60) -ForegroundColor Green
Write-Host ""
