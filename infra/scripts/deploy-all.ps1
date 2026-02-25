# ============================================================================
# deploy-all.ps1 - Desplegar toda la infraestructura
# ============================================================================

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                  MS AGENTS LAB - DEPLOY ALL                  ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$startTime = Get-Date

# Lista de scripts a ejecutar en orden
$scripts = @(
    @{ Name = "auth-permissions-helper.ps1"; Description = "Validar permisos de despliegue"; ShowOnConsole = $false },
    @{ Name = "01-resource-group.ps1"; Description = "Crear Resource Group"; ShowOnConsole = $true },
    @{ Name = "02-foundry-maf.ps1"; Description = "Crear Foundry MAF (AIServices)"; ShowOnConsole = $true },
    @{ Name = "03-m365-service-principal.ps1"; Description = "Crear App Registration + Service Principal"; ShowOnConsole = $true },
    @{ Name = "04-observability.ps1"; Description = "Configurar observabilidad (LAW + AppInsights)"; ShowOnConsole = $true }
)

foreach ($script in $scripts) {
    if ($script.ShowOnConsole) {
        Write-Host ""
        Write-Host ">> $($script.Name) - $($script.Description)" -ForegroundColor Red
    }
    
    $scriptFullPath = Join-Path $scriptPath $script.Name
    
    if (Test-Path $scriptFullPath) {
        try {
            if ($script.Name -in @("02-foundry-maf.ps1", "03-m365-service-principal.ps1", "04-observability.ps1")) {
                $env:SKIP_INFRA_PREREQS = "1"
            } else {
                Remove-Item Env:SKIP_INFRA_PREREQS -ErrorAction SilentlyContinue
            }

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

$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)
$envGeneratedPath = Join-Path $repoRoot ".env.generated"
$envPath = Join-Path $repoRoot ".env"
$envBackupPath = Join-Path $repoRoot ".env.backup"

Write-Host "" 
Write-Host -NoNewline ">> PRE-05" -ForegroundColor Red
Write-Host " - Preparación de .env desde .env.generated"

if (-not (Test-Path $envGeneratedPath)) {
    Write-Host "No se encontró .env.generated en: $envGeneratedPath" -ForegroundColor Red
    exit 1
}

Write-Host "Se va a realizar la copia de configuración para el despliegue web:" -ForegroundColor Yellow
Write-Host "  origen : $envGeneratedPath" -ForegroundColor Yellow
Write-Host "  destino: $envPath" -ForegroundColor Yellow
if (Test-Path $envPath) {
    Write-Host "  backup : $envBackupPath (sobrescribe si existe)" -ForegroundColor Yellow
}

$confirmation = Read-Host "¿Confirmas continuar con backup/copia y ejecutar 05-webapp-m365.ps1? (y/Y)"
if ($confirmation -notin @("y", "Y")) {
    Write-Host "Operación cancelada por el usuario." -ForegroundColor Yellow
    exit 1
}

try {
    if (Test-Path $envPath) {
        Copy-Item -Path $envPath -Destination $envBackupPath -Force
        Write-Host "Backup generado: $envBackupPath" -ForegroundColor Green
    }

    Copy-Item -Path $envGeneratedPath -Destination $envPath -Force
    Write-Host "Copia aplicada: .env.generated -> .env" -ForegroundColor Green
} catch {
    Write-Host "Error preparando .env: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$script05Path = Join-Path $scriptPath "05-webapp-m365.ps1"
if (-not (Test-Path $script05Path)) {
    Write-Host "Script no encontrado: $script05Path" -ForegroundColor Red
    exit 1
}

Write-Host "" 
Write-Host ">> 05-webapp-m365.ps1 - Crear App Service M365" -ForegroundColor Red

try {
    $env:SKIP_INFRA_PREREQS = "1"
    $env:RUNNING_FROM_DEPLOY_ALL = "1"
    & $script05Path
} catch {
    Write-Host "" 
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║ ERROR en 05-webapp-m365.ps1" -ForegroundColor Red
    Write-Host "║ $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    exit 1
} finally {
    Remove-Item Env:SKIP_INFRA_PREREQS -ErrorAction SilentlyContinue
    Remove-Item Env:RUNNING_FROM_DEPLOY_ALL -ErrorAction SilentlyContinue
}

try {
    if (Test-Path $envPath) {
        Copy-Item -Path $envPath -Destination $envBackupPath -Force
        Write-Host "Backup generado (post-05): $envBackupPath" -ForegroundColor Green
    }

    Copy-Item -Path $envGeneratedPath -Destination $envPath -Force
    Write-Host "Copia post-05 aplicada: .env.generated -> .env" -ForegroundColor Green
} catch {
    Write-Host "Error sincronizando .env tras 05: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host ""
Write-Host "$('='*60)" -ForegroundColor Cyan
Write-Host " RESUMEN DE DESPLIEGUE" -ForegroundColor Yellow
Write-Host $('='*60) -ForegroundColor Cyan
Write-Host ""
Write-Host "  INFRAESTRUCTURA DESPLEGADA EXITOSAMENTE" -ForegroundColor Yellow
Write-Host "  Tiempo total: $($duration.Minutes) minutos y $($duration.Seconds) segundos" -ForegroundColor Yellow
Write-Host "  Flujo ejecutado:" -ForegroundColor Yellow
Write-Host "    1) 01-resource-group.ps1" -ForegroundColor Yellow
Write-Host "    2) 02-foundry-maf.ps1" -ForegroundColor Yellow
Write-Host "    3) 03-m365-service-principal.ps1" -ForegroundColor Yellow
Write-Host "    4) 04-observability.ps1" -ForegroundColor Yellow
Write-Host "    5) backup/copia .env.generated -> .env (con confirmación)" -ForegroundColor Yellow
Write-Host "    6) 05-webapp-m365.ps1" -ForegroundColor Yellow
Write-Host "    7) sincronización final .env.generated -> .env" -ForegroundColor Yellow
Write-Host ""
