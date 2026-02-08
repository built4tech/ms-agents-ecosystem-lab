# ============================================================================
# Configuración centralizada del laboratorio
# ============================================================================
# INSTRUCCIONES:
# 1. Copia este archivo a 'lab-config.ps1' en la misma carpeta
# 2. Actualiza los valores según tu entorno de Azure
# 3. lab-config.ps1 está en .gitignore y no se subirá al repositorio
# ============================================================================

# Subscription (dejar vacío para usar la subscription activa)
$script:SubscriptionId = ""  # Ejemplo: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Región
$script:Location = "eastus2"

# Resource Group
$script:ResourceGroupName = "rg-agents-lab"

# AI Foundry Hub
$script:HubName = "hub-agents-lab"

# Recursos dependientes del Hub (nombres generados automáticamente)
$script:StorageAccountName = "stagentslab$(Get-Random -Minimum 1000 -Maximum 9999)"
$script:KeyVaultName = "kv-agents-lab-$(Get-Random -Minimum 1000 -Maximum 9999)"
$script:AppInsightsName = "appi-agents-lab"
$script:LogAnalyticsName = "log-agents-lab"

# Proyectos
$script:Projects = @{
    LangChain = "project-langchain-agents"
    MAF       = "project-maf-agents"
    CrewAI    = "project-crewai-agents"
}

# Modelo a desplegar
$script:ModelName = "gpt-4o-mini"
$script:ModelVersion = "2024-07-18"
$script:ModelSku = "GlobalStandard"
$script:ModelCapacity = 10  # TPM en miles (10 = 10K tokens por minuto)

# Tags para recursos
$script:Tags = @{
    Environment = "lab"
    Project     = "ms-agents-ecosystem-lab"
    Purpose     = "comparative-study"
}

# ============================================================================
# Funciones auxiliares
# ============================================================================

function Get-TagsString {
    $tagPairs = $script:Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
    return $tagPairs -join " "
}

function Write-Step {
    param([string]$Message)
    Write-Host "`n► $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Gray
}

function Write-Endpoint {
    param(
        [string]$Name,
        [string]$Value
    )
    Write-Host "  $Name" -ForegroundColor Yellow -NoNewline
    Write-Host ": $Value" -ForegroundColor White
}
