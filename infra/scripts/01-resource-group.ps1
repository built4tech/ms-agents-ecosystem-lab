# ============================================================================
# 01-resource-group.ps1 - Crear Resource Group
# ============================================================================

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptPath\..\config\lab-config.ps1"
. "$scriptPath\auth-permissions-helper.ps1"
. "$scriptPath\env-generated-helper.ps1"

Write-Host "" 
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                  OBJETIVO DEL SCRIPT                         ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  1) Crear (si no existe) el Resource Group configurado       " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  2) Persistir datos base en .env.generated                   " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "     - AZURE_SUBSCRIPTION_ID                                  " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "     - AZURE_RESOURCE_GROUP                                   " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "     - AZURE_LOCATION                                         " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

$account = Assert-InfraPrerequisites -ForScript "01-resource-group.ps1"

Write-Host "`n$("="*60)" -ForegroundColor Cyan
Write-Host " CREACIÓN DE RESOURCE GROUP" -ForegroundColor Cyan
Write-Host $("="*60) -ForegroundColor Cyan

# Verificar si el RG ya existe
Write-Step "Verificando si el Resource Group existe..."
$rgExists = az group exists --name $script:ResourceGroupName

if ($rgExists -eq "true") {
    Write-Success "Resource Group '$($script:ResourceGroupName)' ya existe"
} else {
    Write-Success "Resource Group inexistente (se procederá a crearlo)"
    Write-Step "Creando Resource Group '$($script:ResourceGroupName)'..."
    
    $tagsString = Get-TagsString
    
    az group create `
        --name $script:ResourceGroupName `
        --location $script:Location `
        --tags $tagsString.Split(" ") `
        --output none
    
    Write-Success "Resource Group creado exitosamente"
}

$null = Update-EnvGeneratedSection -ScriptPath $scriptPath -SectionName "01-resource-group.ps1" -SectionValues @{
    AZURE_SUBSCRIPTION_ID = $account.id
    AZURE_RESOURCE_GROUP  = $script:ResourceGroupName
    AZURE_LOCATION        = $script:Location
}

Write-Host "`n$('-'*60)" -ForegroundColor Gray
Write-Host " ACTUALIZACIÓN DE .env.generated" -ForegroundColor Yellow
Write-Host $('-'*60) -ForegroundColor Gray
Write-Endpoint "AZURE_SUBSCRIPTION_ID" $account.id
Write-Endpoint "AZURE_RESOURCE_GROUP" $script:ResourceGroupName
Write-Endpoint "AZURE_LOCATION" $script:Location
