# ============================================================================
# 04-observability.ps1 - Crear Log Analytics Workspace + Application Insights
# y poblar variables de observabilidad en .env.generated
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
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  1) Validar Resource Group para observabilidad               " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  2) Crear/reutilizar Log Analytics Workspace                 " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  3) Crear/reutilizar Application Insights                    " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  4) Persistir variables de observabilidad en .env.generated  " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan


function Get-LocationToken {
    param([string]$Location)

    if ([string]::IsNullOrWhiteSpace($Location)) {
        return "loc"
    }

    return ([regex]::Replace($Location.ToLowerInvariant(), "[^a-z0-9]", ""))
}

function Find-AvailableLawName {
    param(
        [string]$ResourceGroup,
        [string]$BaseName,
        [string]$Location
    )

    $token = Get-LocationToken -Location $Location
    $candidateBase = "$BaseName-$token"
    if ($candidateBase.Length -gt 63) {
        $candidateBase = $candidateBase.Substring(0, 63).Trim('-')
    }

    for ($i = 0; $i -lt 30; $i++) {
        $candidate = $candidateBase
        if ($i -gt 0) {
            $suffix = "-$i"
            $maxLen = 63 - $suffix.Length
            $candidate = ($candidateBase.Substring(0, [Math]::Min($candidateBase.Length, $maxLen)).Trim('-')) + $suffix
        }

        $existingJson = az monitor log-analytics workspace show `
            --resource-group $ResourceGroup `
            --workspace-name $candidate `
            --output json 2>$null

        if ($LASTEXITCODE -ne 0 -or -not $existingJson) {
            return $candidate
        }
    }

    throw "No se pudo resolver un nombre disponible para Log Analytics en la región deseada."
}

function Find-AvailableAppInsightsName {
    param(
        [string]$ResourceGroup,
        [string]$BaseName,
        [string]$Location
    )

    $token = Get-LocationToken -Location $Location
    $candidateBase = "$BaseName-$token"

    for ($i = 0; $i -lt 30; $i++) {
        $candidate = $candidateBase
        if ($i -gt 0) {
            $candidate = "$candidateBase-$i"
        }

        $existingJson = az monitor app-insights component show `
            --app $candidate `
            --resource-group $ResourceGroup `
            --output json 2>$null

        if ($LASTEXITCODE -ne 0 -or -not $existingJson) {
            return $candidate
        }
    }

    throw "No se pudo resolver un nombre disponible para Application Insights en la región deseada."
}


$account = Assert-InfraPrerequisites -ForScript "04-observability.ps1"

$observabilityLocation = $script:Location
if ($script:ObservabilityLocation -and $script:ObservabilityLocation -ne $script:Location) {
    Write-Host "[WARN] ObservabilityLocation=$($script:ObservabilityLocation) ignorada. Se usa Location=$($script:Location)." -ForegroundColor Yellow
}
$lawName = if ($script:LogAnalyticsWorkspaceName) { $script:LogAnalyticsWorkspaceName } else { "law-agents-lab" }
$appInsightsName = if ($script:ApplicationInsightsName) { $script:ApplicationInsightsName } else { "appi-agents-lab" }

$otelServiceName = if ($script:OtelServiceName) { $script:OtelServiceName } else { "agent_viewer" }
$otelServiceNamespace = if ($script:OtelServiceNamespace) { $script:OtelServiceNamespace } else { "agent_viewer_Name_Space" }

Write-Step "Verificando Resource Group '$($script:ResourceGroupName)'..."
$rgExists = az group exists --name $script:ResourceGroupName
if ($rgExists -eq "false") {
    Write-Error "El Resource Group '$($script:ResourceGroupName)' no existe"
    Write-Host "Ejecuta primero: .\01-resource-group.ps1" -ForegroundColor Yellow
    exit 1
}
Write-Success "Resource Group validado"

Write-Host "`n$('='*60)" -ForegroundColor Cyan
Write-Host " OBSERVABILIDAD - LOG ANALYTICS + APP INSIGHTS" -ForegroundColor Cyan
Write-Host $('='*60) -ForegroundColor Cyan

Write-Step "Resolviendo Log Analytics Workspace '$lawName'..."
$lawJson = az monitor log-analytics workspace show `
    --resource-group $script:ResourceGroupName `
    --workspace-name $lawName `
    --output json 2>$null

$lawResource = $null
if ($LASTEXITCODE -eq 0 -and $lawJson) {
    $lawResource = $lawJson | ConvertFrom-Json
}

$lawEffectiveLocation = $observabilityLocation
$lawEffectiveName = $lawName

if ($lawResource) {
    if ($lawResource.location -eq $observabilityLocation) {
        $lawEffectiveLocation = $lawResource.location
        Write-Success "Log Analytics Workspace existente reutilizado"
    } else {
        Write-Host "[WARN] LAW '$lawName' existe en '$($lawResource.location)' y no coincide con '$observabilityLocation'." -ForegroundColor Yellow
        $lawEffectiveName = Find-AvailableLawName -ResourceGroup $script:ResourceGroupName -BaseName $lawName -Location $observabilityLocation
        Write-Step "Creando LAW alternativo '$lawEffectiveName' en '$observabilityLocation'..."
        az monitor log-analytics workspace create `
            --resource-group $script:ResourceGroupName `
            --workspace-name $lawEffectiveName `
            --location $observabilityLocation `
            --retention-time 30 `
            --output none
        Write-Success "Log Analytics Workspace alternativo creado"
    }
} else {
    Write-Success "Log Analytics Workspace no existente (se procederá a crear)"
    Write-Step "Creando Log Analytics Workspace '$lawName' en '$observabilityLocation'..."
    az monitor log-analytics workspace create `
        --resource-group $script:ResourceGroupName `
        --workspace-name $lawEffectiveName `
        --location $observabilityLocation `
        --retention-time 30 `
        --output none
    Write-Success "Log Analytics Workspace creado"
}

Write-Step "Verificando disponibilidad de Log Analytics Workspace '$lawEffectiveName'..."
$workspaceId = az monitor log-analytics workspace show `
    --resource-group $script:ResourceGroupName `
    --workspace-name $lawEffectiveName `
    --query id `
    --output tsv

if ([string]::IsNullOrWhiteSpace($workspaceId)) {
    Write-Error "No se pudo obtener el ID del Log Analytics Workspace"
    exit 1
}

Write-Success "Log Analytics Workspace listo"

Write-Step "Resolviendo Application Insights '$appInsightsName'..."
$appiJson = az monitor app-insights component show `
    --app $appInsightsName `
    --resource-group $script:ResourceGroupName `
    --output json 2>$null

$appiResource = $null
if ($LASTEXITCODE -eq 0 -and $appiJson) {
    $appiResource = $appiJson | ConvertFrom-Json
}

$appiEffectiveLocation = $observabilityLocation
$appiEffectiveName = $appInsightsName

if ($appiResource) {
    if ($appiResource.location -eq $observabilityLocation) {
        $appiEffectiveLocation = $appiResource.location
        Write-Success "Application Insights existente reutilizado"
    } else {
        Write-Host "[WARN] App Insights '$appInsightsName' existe en '$($appiResource.location)' y no coincide con '$observabilityLocation'." -ForegroundColor Yellow
        $appiEffectiveName = Find-AvailableAppInsightsName -ResourceGroup $script:ResourceGroupName -BaseName $appInsightsName -Location $observabilityLocation
        Write-Step "Creando App Insights alternativo '$appiEffectiveName' en '$observabilityLocation'..."
        az monitor app-insights component create `
            --app $appiEffectiveName `
            --resource-group $script:ResourceGroupName `
            --location $observabilityLocation `
            --workspace $workspaceId `
            --application-type web `
            --kind web `
            --output none
        Write-Success "Application Insights alternativo creado"
    }
} else {
    Write-Success "Application Insights no existente (se procederá a crear)"
    Write-Step "Creando Application Insights '$appInsightsName' vinculado a Log Analytics..."
    az monitor app-insights component create `
        --app $appiEffectiveName `
        --resource-group $script:ResourceGroupName `
        --location $observabilityLocation `
        --workspace $workspaceId `
        --application-type web `
        --kind web `
        --output none
    Write-Success "Application Insights creado"
}

$connectionString = az monitor app-insights component show `
    --app $appiEffectiveName `
    --resource-group $script:ResourceGroupName `
    --query connectionString `
    --output tsv

if ([string]::IsNullOrWhiteSpace($connectionString)) {
    Write-Error "No se pudo obtener APPLICATIONINSIGHTS_CONNECTION_STRING"
    exit 1
}

$null = Update-EnvGeneratedSection -ScriptPath $scriptPath -SectionName "04-observability.ps1" -SectionValues @{
    APPLICATIONINSIGHTS_CONNECTION_STRING = $connectionString
    ENABLE_OBSERVABILITY                  = "true"
    ENABLE_A365_OBSERVABILITY_EXPORTER    = "false"
    OTEL_SERVICE_NAME                     = $otelServiceName
    OTEL_SERVICE_NAMESPACE                = $otelServiceNamespace
}

Write-Host "`n$('-'*60)" -ForegroundColor Gray
Write-Host " ACTUALIZACIÓN DE .env.generated" -ForegroundColor Yellow
Write-Host $('-'*60) -ForegroundColor Gray
Write-Endpoint "APPLICATIONINSIGHTS_CONNECTION_STRING" "(configurada en .env.generated)"
Write-Endpoint "ENABLE_OBSERVABILITY" "true"
Write-Endpoint "ENABLE_A365_OBSERVABILITY_EXPORTER" "false"
Write-Endpoint "OTEL_SERVICE_NAME" $otelServiceName
Write-Endpoint "OTEL_SERVICE_NAMESPACE" $otelServiceNamespace