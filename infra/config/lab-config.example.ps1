# ============================================================================
# Configuración centralizada del laboratorio - Foundry MAF (AIServices)
# ============================================================================

# Subscription (dejar vacío para usar la subscription activa)
$script:SubscriptionId = "00000000000000000000000000000000"

# Región
$script:Location = "eastus2"

# Web App / App Service (excepción regional por licenciamiento)
$script:WebAppLocation = "spaincentral"

# Resource Group
$script:ResourceGroupName = "rg-agents-lab"

# Modelo a desplegar en el recurso Foundry
$script:ModelName = "gpt-4o-mini"
$script:ModelVersion = "2024-07-18"
$script:ModelSku = "GlobalStandard"
$script:ModelCapacity = 10  # TPM en miles (10 = 10K tokens por minuto)

# Recurso Foundry para MAF
$script:FoundryName = "agent-identity-viewer"

# Observabilidad OTel (valores fijos)
$script:OtelServiceName = "agent-identity-viewer"
$script:OtelServiceNamespace = "agent-idetity-viewer-name-space"

# Tags para recursos
$script:Tags = @{
    Environment = "lab"
    Project     = "agents-ecosystem-study"
    Purpose     = "agent study and demos"
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
    Write-Host "`n>> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "[X] $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Gray
}

function Write-Endpoint {
    param(
        [string]$Name,
        [string]$Value
    )
    Write-Host -NoNewline "    $Name" -ForegroundColor Yellow
    Write-Host ": $Value" -ForegroundColor White
}
