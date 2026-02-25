# ============================================================================
# destroy-all.ps1 - Eliminar toda la infraestructura
# ============================================================================

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptPath\..\config\lab-config.ps1"

function Get-RepoRoot {
    return Split-Path -Parent (Split-Path -Parent $scriptPath)
}

function Get-DotEnvValue {
    param(
        [string]$EnvPath,
        [string]$Key
    )

    if (-not (Test-Path $EnvPath)) { return $null }

    $line = Get-Content -Path $EnvPath | Where-Object { $_ -match "^\s*$Key\s*=" } | Select-Object -First 1
    if (-not $line) { return $null }

    return (($line -split "=", 2)[1]).Trim()
}

function Write-Section {
    param([string]$Title)
    Write-Host "`n$('-'*60)" -ForegroundColor DarkGray
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host $('-'*60) -ForegroundColor DarkGray
}

function Write-Item {
    param(
        [string]$Label,
        [string]$Value
    )
    Write-Host -NoNewline "  - $Label" -ForegroundColor Yellow
    Write-Host ": $Value" -ForegroundColor White
}

function Confirm-DeleteLocalEnvFiles {
    param(
        [string]$EnvPath,
        [string]$EnvGeneratedPath
    )

    Write-Section "LIMPIEZA LOCAL (ARCHIVOS .ENV)"
    Write-Item "Archivo" $EnvPath
    Write-Item "Archivo" $EnvGeneratedPath

    $shouldDeleteFiles = Read-Host "  ¿Deseas eliminar estos archivos locales obsoletos? (s/N)"
    if ($env:FORCE_DESTROY -eq "1") { $shouldDeleteFiles = "s" }

    if ($shouldDeleteFiles -notin @("s", "S")) {
        Write-Info "Se mantienen los archivos locales de entorno."
        return
    }

    if (Test-Path $EnvPath) {
        Remove-Item -Path $EnvPath -Force
        Write-Success ".env eliminado"
    } else {
        Write-Info ".env no existe"
    }

    if (Test-Path $EnvGeneratedPath) {
        Remove-Item -Path $EnvGeneratedPath -Force
        Write-Success ".env.generated eliminado"
    } else {
        Write-Info ".env.generated no existe"
    }
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║                                                              ║" -ForegroundColor Red
Write-Host "║          MS AGENTS ECOSYSTEM LAB - DESTROY ALL               ║" -ForegroundColor Red
Write-Host "║                                                              ║" -ForegroundColor Red
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""

$repoRoot = Get-RepoRoot
$envPath = Join-Path $repoRoot ".env"
$envGeneratedPath = Join-Path $repoRoot ".env.generated"
$appId = Get-DotEnvValue -EnvPath $envPath -Key "MICROSOFT_APP_ID"

Write-Section "ALCANCE DE ELIMINACIÓN"
Write-Host "  Recursos vinculados al Resource Group (se eliminan con RG):" -ForegroundColor White
Write-Item "Resource Group" $script:ResourceGroupName
$foundryDisplayName = if ($script:FoundryName) { $script:FoundryName } else { "(no configurado)" }
Write-Item "Foundry" $foundryDisplayName
Write-Item "App Service / Plan" "incluidos en el Resource Group"
Write-Item "Observabilidad" "Log Analytics + App Insights"

Write-Host "`n  Recursos globales (Entra ID, fuera del RG):" -ForegroundColor White
if (-not [string]::IsNullOrWhiteSpace($appId)) {
    Write-Item "App Registration" $appId
    Write-Item "Service Principal" $appId
} else {
    Write-Item "App Registration / Service Principal" "no detectado en .env (MICROSOFT_APP_ID)"
}

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
if ($script:FoundryName) { $foundryNames += $script:FoundryName }

# Establecer subscription si se especificó
if ($script:SubscriptionId) {
    Write-Step "Estableciendo subscription:"
    az account set --subscription $script:SubscriptionId | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Subscripción establecida en: $($script:SubscriptionId)"
    } else {
        Write-Error "No se pudo establecer la subscription '$($script:SubscriptionId)'"
        exit 1
    }
}

function Invoke-FoundryCleanup {
    param(
        [string[]] $Names,
        [bool] $RemoveActiveFirst
    )

    if (-not $Names -or $Names.Count -eq 0) { return }

    foreach ($foundryName in $Names) {
        Write-Info "Procesando '$foundryName'"

        if ($RemoveActiveFirst) {
            $foundryExists = az cognitiveservices account show `
                --name $foundryName `
                --resource-group $script:ResourceGroupName `
                --output json 2>$null

            if ($foundryExists) {
                Write-Info "  Intentando eliminar cuenta activa..."
                $deleteOutput = az cognitiveservices account delete `
                    --name $foundryName `
                    --resource-group $script:ResourceGroupName `
                    --output none 2>&1 | Out-String

                if ($LASTEXITCODE -eq 0) {
                    Write-Success "  Eliminación de cuenta Foundry solicitada"
                } else {
                    $isNestedResourceBlock =
                        ($deleteOutput -match "CannotDeleteResource") -and
                        ($deleteOutput -match "nested resources")

                    if ($isNestedResourceBlock) {
                        Write-Info "  Foundry tiene recursos hijos (projects). Se eliminará al borrar el RG y luego se purgará soft-delete."
                    }
                    else {
                        throw "Error eliminando Foundry '$foundryName': $deleteOutput"
                    }
                }
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
    Write-Section "LIMPIEZA PREVIA DE FOUNDRY"
    Write-Step "Preparando limpieza y purga para evitar soft-delete residual..."
    Invoke-FoundryCleanup -Names $foundryNames -RemoveActiveFirst:$true
    Write-Step "Verificando soft-delete pendientes antes de eliminar el RG..."
    Invoke-FoundryPurgeLoop -Names $foundryNames -Retries 6 -DelaySeconds 10
}

if (-not [string]::IsNullOrWhiteSpace($appId)) {
    Write-Section "LIMPIEZA GLOBAL (ENTRA ID)"

    Write-Step "Eliminando service principal global '$appId'..."
    $spExists = az ad sp show --id $appId --output json 2>$null
    if ($spExists) {
        az ad sp delete --id $appId --output none
        Write-Success "Service principal eliminado"
    } else {
        Write-Info "Service principal no encontrado o ya eliminado"
    }

    Write-Step "Eliminando app registration global '$appId'..."
    $appExists = az ad app show --id $appId --output json 2>$null
    if ($appExists) {
        az ad app delete --id $appId --output none
        Write-Success "App registration eliminada"
    } else {
        Write-Info "App registration no encontrada o ya eliminada"
    }
} else {
    Write-Section "LIMPIEZA GLOBAL (ENTRA ID)"
    Write-Info "No se encontró MICROSOFT_APP_ID en .env; se omite eliminación de recursos globales"
}

Write-Section "ELIMINACIÓN DEL RESOURCE GROUP"
Write-Step "Verificando si el Resource Group existe..."

$rgExists = az group exists --name $script:ResourceGroupName

if ($rgExists -eq "false") {
    Write-Host ""
    Write-Host "  El Resource Group '$($script:ResourceGroupName)' no existe." -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

Write-Success "Resource Group detectado"

Write-Step "Eliminando Resource Group '$($script:ResourceGroupName)'..."
Write-Info "Esto puede tardar varios minutos..."

$startTime = Get-Date

az group delete `
    --name $script:ResourceGroupName `
    --yes `
    --no-wait

if ($LASTEXITCODE -eq 0) {
    Write-Success "Solicitud de eliminación enviada"
} else {
    Write-Error "No se pudo lanzar la eliminación del Resource Group"
    exit 1
}

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

    $maxWaitSeconds = [int](${env:DESTROY_WAIT_SECONDS} | ForEach-Object { if ($_ -as [int]) { $_ } else { 1800 } })
    $pollSeconds = 10
    $elapsedSeconds = 0
    $lastState = $null

    while ($true) {
        $rgStillExists = az group exists --name $script:ResourceGroupName
        if ($rgStillExists -eq "false") {
            break
        }

        # Mostrar estado del RG si sigue existiendo
        $state = az group show --name $script:ResourceGroupName --query "properties.provisioningState" -o tsv 2>$null
        if ($state -and $state -ne $lastState) {
            Write-Host -NoNewline "[$state]"
            $lastState = $state
        }
        Write-Host "." -NoNewline

        Start-Sleep -Seconds $pollSeconds
        $elapsedSeconds += $pollSeconds

        if ($elapsedSeconds -ge $maxWaitSeconds) {
            Write-Host ""
            Write-Host "  Tiempo de espera agotado (${maxWaitSeconds}s). El RG sigue existiendo." -ForegroundColor Yellow
            break
        }
    }

    $endTime = Get-Date
    $duration = $endTime - $startTime

    if ($rgStillExists -eq "false") {
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

        Confirm-DeleteLocalEnvFiles -EnvPath $envPath -EnvGeneratedPath $envGeneratedPath
    }
} else {
    Confirm-DeleteLocalEnvFiles -EnvPath $envPath -EnvGeneratedPath $envGeneratedPath
}
