# ============================================================================
# deploy-all.ps1 - Desplegar toda la infraestructura
# ============================================================================

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                                                              ║" -ForegroundColor Cyan
Write-Host "║          MS AGENTS ECOSYSTEM LAB - DEPLOY ALL               ║" -ForegroundColor Cyan
Write-Host "║                                                              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$startTime = Get-Date

# Lista de scripts a ejecutar en orden
# NOTA: 05-webapp-m365.ps1 NO debe ejecutarse aquí porque requiere:
# 1) ejecutar scripts previos de identidad/observabilidad,
# 2) completar secciones 03 y 04 en .env.generated,
# 3) copiar manualmente .env.generated a .env.
$scripts = @(
    @{ Name = "auth-permissions-helper.ps1"; Description = "Validar permisos de despliegue" },
    @{ Name = "01-resource-group.ps1"; Description = "Crear Resource Group" },
    @{ Name = "02-foundry-maf.ps1"; Description = "Crear Foundry MAF (AIServices)" }
)

$totalScripts = $scripts.Count
$currentScript = 0

foreach ($script in $scripts) {
    $currentScript++
    $progress = [math]::Round(($currentScript / $totalScripts) * 100)
    
    Write-Host ""
    Write-Host "┌──────────────────────────────────────────────────────────────┐" -ForegroundColor Blue
    Write-Host "│ [$currentScript/$totalScripts] $($script.Description.PadRight(50)) │" -ForegroundColor Blue
    Write-Host "└──────────────────────────────────────────────────────────────┘" -ForegroundColor Blue
    
    $scriptFullPath = Join-Path $scriptPath $script.Name
    
    if (Test-Path $scriptFullPath) {
        try {
            & $scriptFullPath
        } catch {
            Write-Host ""
            Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
            Write-Host "║ ERROR en $($script.Name)" -ForegroundColor Red
            Write-Host "║ $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "  Script no encontrado: $scriptFullPath" -ForegroundColor Red
        exit 1
    }
}

$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║            INFRAESTRUCTURA DESPLEGADA EXITOSAMENTE           ║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Tiempo total: $($duration.Minutes) minutos y $($duration.Seconds) segundos" -ForegroundColor Gray
Write-Host ""
Write-Host "  Siguiente paso (manual):" -ForegroundColor Yellow
Write-Host "    1) .\03-m365-service-principal.ps1" -ForegroundColor Yellow
Write-Host "    2) .\04-observability.ps1" -ForegroundColor Yellow
Write-Host "    3) copiar .env.generated -> .env" -ForegroundColor Yellow
Write-Host "    4) .\05-webapp-m365.ps1" -ForegroundColor Yellow
Write-Host "  (05-webapp-m365.ps1 no forma parte de deploy-all.ps1 por dependencia de configuración manual)" -ForegroundColor Gray
Write-Host ""
