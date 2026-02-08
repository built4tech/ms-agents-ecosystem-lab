# ============================================================================
# 00-auth.ps1 - Verificar autenticación y subscription
# ============================================================================

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptPath\..\config\lab-config.ps1"

Write-Host "`n$("="*60)" -ForegroundColor Magenta
Write-Host " VERIFICACIÓN DE AUTENTICACIÓN" -ForegroundColor Magenta
Write-Host $("="*60) -ForegroundColor Magenta

# ----------------------------------------------------------------------------
# Verificar si se ejecuta como Administrador
# ----------------------------------------------------------------------------
Write-Step "Verificando permisos de ejecución..."

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "Este script requiere permisos de Administrador"
    Write-Info "Ejecuta PowerShell como Administrador o usa:"
    Write-Info "  Start-Process powershell -Verb RunAs -ArgumentList '-NoExit', '-File', '$($MyInvocation.MyCommand.Path)'"
    exit 1
}

Write-Success "Ejecutando como Administrador"

# Verificar si Azure CLI está instalado
Write-Step "Verificando Azure CLI..."
try {
    $azVersion = az version --output json | ConvertFrom-Json
    Write-Success "Azure CLI instalado (versión: $($azVersion.'azure-cli'))"
} catch {
    Write-Error "Azure CLI no está instalado. Instálalo desde: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
}

# Verificar si hay sesión activa
Write-Step "Verificando sesión de Azure..."
$account = az account show --output json 2>$null | ConvertFrom-Json

if (-not $account) {
    Write-Info "No hay sesión activa. Iniciando login..."
    az login
    $account = az account show --output json | ConvertFrom-Json
}

Write-Success "Sesión activa"
Write-Info "Usuario: $($account.user.name)"
Write-Info "Tenant: $($account.tenantId)"

# Establecer subscription si se especificó
if ($script:SubscriptionId) {
    Write-Step "Estableciendo subscription: $($script:SubscriptionId)"
    az account set --subscription $script:SubscriptionId
    $account = az account show --output json | ConvertFrom-Json
}

Write-Host "`n$("-"*60)" -ForegroundColor Gray
Write-Host " SUBSCRIPTION ACTIVA" -ForegroundColor Yellow
Write-Host $("-"*60) -ForegroundColor Gray
Write-Endpoint "ID" $account.id
Write-Endpoint "Nombre" $account.name
Write-Endpoint "Estado" $account.state

# Verificar que la región tiene disponibilidad del modelo
Write-Step "Verificando disponibilidad en región $($script:Location)..."
Write-Success "Región configurada: $($script:Location)"
Write-Info "Nota: Asegúrate de que gpt-4o-mini está disponible en esta región"

Write-Host "`n$("="*60)" -ForegroundColor Green
Write-Host " AUTENTICACION VERIFICADA" -ForegroundColor Green
Write-Host $("="*60) -ForegroundColor Green
Write-Host ""
