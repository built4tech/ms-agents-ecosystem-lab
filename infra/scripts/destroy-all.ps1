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

if ($env:FORCE_DESTROY -eq "1") { $confirmation = "ELIMINAR" }

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

function Invoke-FoundryCleanup {
    param(
        [string[]] $Names,
        [bool] $RemoveActiveFirst
    )

    if (-not $Names -or $Names.Count -eq 0) { return }

    foreach ($foundryName in $Names) {
        Write-Info "Procesando $foundryName"

        if ($RemoveActiveFirst) {
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
        }

        $listDeletedCmd = @(
            "cognitiveservices", "account", "list-deleted",
            "--output", "json"
        )
        if ($script:SubscriptionId) { $listDeletedCmd += @("--subscription", $script:SubscriptionId) }

        $deletedList = az @listDeletedCmd 2>$null | ConvertFrom-Json
        $deleted = $deletedList | Where-Object { $_.name -eq $foundryName }

        if ($deleted) {
            Write-Info "  Purga de soft-delete..."
            $purgeCmd = @(
                "cognitiveservices", "account", "purge",
                "--name", $foundryName,
                "--resource-group", $script:ResourceGroupName,
                "--location", $script:Location
            )
            if ($script:SubscriptionId) { $purgeCmd += @("--subscription", $script:SubscriptionId) }
            $purgeCmd += @("--output", "none")

            az @purgeCmd
            Write-Success "  Purga completada"
        } else {
            Write-Info "  No hay soft-delete para purgar"
        }
    }
}

function Invoke-FoundryPurgeLoop {
    param(
        [string[]] $Names,
        [int] $Retries = 12,
        [int] $DelaySeconds = 10
    )

    if (-not $Names -or $Names.Count -eq 0) { return }

    for ($i = 1; $i -le $Retries; $i++) {
        $anyDeleted = $false

        foreach ($foundryName in $Names) {
            $listDeletedCmd = @(
                "cognitiveservices", "account", "list-deleted",
                "--output", "json"
            )
            if ($script:SubscriptionId) { $listDeletedCmd += @("--subscription", $script:SubscriptionId) }

            $deletedList = az @listDeletedCmd 2>$null | ConvertFrom-Json
            $deleted = $deletedList | Where-Object { $_.name -eq $foundryName }

            if ($deleted) {
                $anyDeleted = $true
                Write-Info "  Intento ${i}: purgando soft-delete de $foundryName"
                $purgeCmd = @(
                    "cognitiveservices", "account", "purge",
                    "--name", $foundryName,
                    "--resource-group", $script:ResourceGroupName,
                    "--location", $script:Location
                )
                if ($script:SubscriptionId) { $purgeCmd += @("--subscription", $script:SubscriptionId) }
                $purgeCmd += @("--output", "none")

                az @purgeCmd
                Write-Success "  Purga completada para $foundryName"
            }
        }

        if (-not $anyDeleted) { break }
        Start-Sleep -Seconds $DelaySeconds
    }
}

# Intentar eliminar y purgar los recursos Foundry antes de eliminar el RG para evitar soft-delete colgando
# Se ejecuta antes de comprobar si existe el Resource Group porque aunque el RG no exista, podrían existir recursos Foundry en estado soft-deleted que bloqueen futuras creaciones
if ($foundryNames.Count -gt 0) {
    Write-Step "Eliminando y purgando recursos Foundry (AIServices) para evitar soft-delete..."
    Invoke-FoundryCleanup -Names $foundryNames -RemoveActiveFirst:$true
    Write-Step "Verificando/purgando soft-delete pendientes antes de eliminar el RG..."
    Invoke-FoundryPurgeLoop -Names $foundryNames -Retries 6 -DelaySeconds 10
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

# Purga temprana tras solicitar la eliminación del RG, en caso de que aparezcan soft-deletes durante la operación
if ($foundryNames.Count -gt 0) {
    Write-Step "Verificando/purgando soft-delete tras lanzar la eliminación del RG..."
    Invoke-FoundryPurgeLoop -Names $foundryNames -Retries 6 -DelaySeconds 10
}

# Esperar confirmación opcional
$waitForDeletion = Read-Host "  ¿Deseas esperar a que termine la eliminación? (s/N)"
if ($env:FORCE_DESTROY -eq "1") { $waitForDeletion = "s" }

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
    Write-Step "Verificando y purgando recursos Foundry en soft-delete tras eliminar el RG..."
    Invoke-FoundryPurgeLoop -Names $foundryNames -Retries 6 -DelaySeconds 10
    
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
