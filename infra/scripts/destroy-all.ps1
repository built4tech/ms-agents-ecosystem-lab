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
Write-Host "    └── Foundry (AIServices) y deployments" -ForegroundColor Gray
Write-Host "        └── Proyectos para agentes (projects)" -ForegroundColor Gray
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

$foundryNames = @()
foreach ($proj in $script:Projects.GetEnumerator()) {
    if ($proj.Value.FoundryName) { $foundryNames += $proj.Value.FoundryName }
}

# Establecer subscription si se especificó
if ($script:SubscriptionId) {
    Write-Step "Estableciendo subscription: $($script:SubscriptionId)"
    az account set --subscription $script:SubscriptionId | Out-Null
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

# Intentar eliminar y purgar los recursos Foundry antes de eliminar el RG para evitar soft-delete colgando
if ($foundryNames.Count -gt 0) {
    Write-Step "Eliminando y purgando recursos Foundry (AIServices) para evitar soft-delete..."

    foreach ($foundryName in $foundryNames) {
        Write-Info "Procesando $foundryName"

        # Si existe activo, eliminarlo primero
        $foundryExists = az cognitiveservices account show `
            --name $foundryName `
            --resource-group $script:ResourceGroupName `
            --output json 2>$null

        if ($foundryExists) {
            Write-Info "  Eliminando cuenta activa..."
            az cognitiveservices account delete `
                --name $foundryName `
                --resource-group $script:ResourceGroupName `
                --output none
        }

        # Purgar si está soft-deleted
        $deletedList = az cognitiveservices account list-deleted `
            --location $script:Location `
            --subscription $script:SubscriptionId `
            --output json 2>$null | ConvertFrom-Json

        $deleted = $deletedList | Where-Object { $_.name -eq $foundryName }

        if ($deleted) {
            Write-Info "  Purga de soft-delete..."
            $purgeCmd = @(
                "az", "cognitiveservices", "account", "purge",
                "--name", $foundryName,
                "--reource-group", $script:ResourceGroupName,
                "--location", $script:Location,
                "--subscription", $script:SubscriptionId
            )
            if ($script:SubscriptionId) { $purgeCmd += @("--subscription", $script:SubscriptionId) }
            $purgeCmd += "--output"; $purgeCmd += "none"

            & @purgeCmd
            Write-Success "  Purga completada"
        } else {
            Write-Info "  No hay soft-delete para purgar"
        }
    }
}

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
