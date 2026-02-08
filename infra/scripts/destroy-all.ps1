# ============================================================================
# destroy-all.ps1 - Eliminar toda la infraestructura
# ============================================================================

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptPath\..\config\lab-config.ps1"

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║                                                              ║" -ForegroundColor Red
Write-Host "║          MS AGENTS ECOSYSTEM LAB - DESTROY ALL              ║" -ForegroundColor Red
Write-Host "║                                                              ║" -ForegroundColor Red
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""

# Mostrar qué se va a eliminar
Write-Host "  Se eliminarán los siguientes recursos:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Resource Group: $($script:ResourceGroupName)" -ForegroundColor White
Write-Host "    └── AI Hub: $($script:HubName)" -ForegroundColor Gray
Write-Host "        ├── Project: $($script:Projects.Foundry)" -ForegroundColor Gray
Write-Host "        ├── Project: $($script:Projects.MAF)" -ForegroundColor Gray
Write-Host "        └── Project: $($script:Projects.CrewAI)" -ForegroundColor Gray
Write-Host "    └── Storage Account" -ForegroundColor Gray
Write-Host "    └── Key Vault" -ForegroundColor Gray
Write-Host "    └── Application Insights" -ForegroundColor Gray
Write-Host "    └── Log Analytics Workspace" -ForegroundColor Gray
Write-Host ""

# Confirmar eliminación
Write-Host "  ⚠️  ESTA ACCIÓN ES IRREVERSIBLE" -ForegroundColor Red
Write-Host ""
$confirmation = Read-Host "  ¿Estás seguro? Escribe 'ELIMINAR' para confirmar"

if ($confirmation -ne "ELIMINAR") {
    Write-Host ""
    Write-Host "  Operación cancelada." -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

Write-Host ""
Write-Step "Verificando si el Resource Group existe..."

$rgExists = az group exists --name $script:ResourceGroupName

if ($rgExists -eq "false") {
    Write-Host ""
    Write-Host "  El Resource Group '$($script:ResourceGroupName)' no existe." -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

Write-Step "Eliminando Resource Group '$($script:ResourceGroupName)'..."
Write-Info "Esto puede tardar varios minutos..."

$startTime = Get-Date

az group delete `
    --name $script:ResourceGroupName `
    --yes `
    --no-wait

Write-Host ""
Write-Host "  La eliminación se ha iniciado en segundo plano." -ForegroundColor Yellow
Write-Host "  Puedes verificar el estado en el portal de Azure." -ForegroundColor Yellow
Write-Host ""

# Esperar confirmación opcional
$waitForDeletion = Read-Host "  ¿Deseas esperar a que termine la eliminación? (s/N)"

if ($waitForDeletion -eq "s" -or $waitForDeletion -eq "S") {
    Write-Host ""
    Write-Info "Esperando a que se complete la eliminación..."
    
    while ($true) {
        $rgStillExists = az group exists --name $script:ResourceGroupName
        if ($rgStillExists -eq "false") {
            break
        }
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 10
    }
    
    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    Write-Host ""
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                                                              ║" -ForegroundColor Green
    Write-Host "║            INFRAESTRUCTURA ELIMINADA EXITOSAMENTE            ║" -ForegroundColor Green
    Write-Host "║                                                              ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Tiempo total: $($duration.Minutes) minutos y $($duration.Seconds) segundos" -ForegroundColor Gray
    Write-Host ""
}
