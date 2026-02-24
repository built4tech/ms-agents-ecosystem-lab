function Get-RepoRootFromScriptPath {
    param([string]$ScriptPath)
    return Split-Path -Parent (Split-Path -Parent $ScriptPath)
}

function Get-EnvGeneratedDateStamp {
    return (Get-Date -Format "dd-MM-yy HH:mm")
}

function Get-EnvGeneratedDefaults {
    return [ordered]@{
        AZURE_SUBSCRIPTION_ID                    = ""
        AZURE_RESOURCE_GROUP                     = ""
        AZURE_LOCATION                           = ""
        ENDPOINT_API                             = ""
        ENDPOINT_OPENAI                          = ""
        DEPLOYMENT_NAME                          = ""
        PROJECT_NAME                             = ""
        API_VERSION                              = ""
        AGENT_HOST                               = ""
        PORT                                     = ""
        MICROSOFT_APP_ID                         = ""
        MICROSOFT_APP_PASSWORD                   = ""
        MICROSOFT_APP_TYPE                       = ""
        MICROSOFT_APP_TENANTID                   = ""
        APPLICATIONINSIGHTS_CONNECTION_STRING    = "InstrumentationKey="
        ENABLE_OBSERVABILITY                     = ""
        ENABLE_A365_OBSERVABILITY_EXPORTER       = ""
        OTEL_SERVICE_NAME                        = ""
        OTEL_SERVICE_NAMESPACE                   = ""
        WEB_APP_NAME                             = ""
    }
}

function Get-EnvGeneratedSectionNames {
    return @(
        "01-resource-group.ps1",
        "02-foundry-maf.ps1",
        "03-m365-service-principal.ps1",
        "04-observability.ps1",
        "05-webapp-m365.ps1"
    )
}

function Read-EnvGeneratedState {
    param([string]$EnvPath)

    $values = Get-EnvGeneratedDefaults
    $dates = @{}

    foreach ($section in Get-EnvGeneratedSectionNames) {
        $dates[$section] = Get-EnvGeneratedDateStamp
    }

    if (-not (Test-Path $EnvPath)) {
        return @{
            Values = $values
            Dates  = $dates
        }
    }

    $lines = Get-Content -Path $EnvPath

    foreach ($line in $lines) {
        if ($line -match '^\s*([^#=\s][^=]*)=(.*)$') {
            $name = $matches[1].Trim()
            $value = $matches[2]
            if ($values.Contains($name)) {
                $values[$name] = $value
            }
        }

        if ($line -match '^#\s*Fichero:\s*([^|]+)\|\s*Fecha:\s*(\d{2}-\d{2}-\d{2}\s\d{2}:\d{2})\s*$') {
            $sectionName = $matches[1].Trim()
            $dateValue = $matches[2].Trim()
            if ($dates.ContainsKey($sectionName)) {
                $dates[$sectionName] = $dateValue
            }
        }
    }

    return @{
        Values = $values
        Dates  = $dates
    }
}

function ConvertTo-EnvGeneratedContent {
    param(
        [hashtable]$Values,
        [hashtable]$Dates
    )

@"
# ============================================================================
# Fichero: 01-resource-group.ps1 | Fecha: $($Dates["01-resource-group.ps1"])
# ============================================================================

# Configuración común de Azure
AZURE_SUBSCRIPTION_ID=$($Values.AZURE_SUBSCRIPTION_ID)
AZURE_RESOURCE_GROUP=$($Values.AZURE_RESOURCE_GROUP)
AZURE_LOCATION=$($Values.AZURE_LOCATION)

# ============================================================================
# Fichero: 02-foundry-maf.ps1 | Fecha: $($Dates["02-foundry-maf.ps1"])
# ============================================================================
ENDPOINT_API=$($Values.ENDPOINT_API)
ENDPOINT_OPENAI=$($Values.ENDPOINT_OPENAI)
DEPLOYMENT_NAME=$($Values.DEPLOYMENT_NAME)
PROJECT_NAME=$($Values.PROJECT_NAME)
API_VERSION=$($Values.API_VERSION)

# ----------------------------------------------------------------------------
# Fichero: 03-m365-service-principal.ps1 | Fecha: $($Dates["03-m365-service-principal.ps1"])
# ----------------------------------------------------------------------------
# Host/port donde corre el servicio HTTP del agente para pruebas con Bot/Playground.
AGENT_HOST=$($Values.AGENT_HOST)
PORT=$($Values.PORT)
# App registration (Entra ID) que representa el bot/agent endpoint.
MICROSOFT_APP_ID=$($Values.MICROSOFT_APP_ID)
# Secreto cliente de la app registration
MICROSOFT_APP_PASSWORD=$($Values.MICROSOFT_APP_PASSWORD)
# Tipo de aplicación para autenticación del SDK. Valor habitual para escenarios enterprise: MultiTenant.
MICROSOFT_APP_TYPE=$($Values.MICROSOFT_APP_TYPE)
# Tenant ID (Directory ID) de Entra.
MICROSOFT_APP_TENANTID=$($Values.MICROSOFT_APP_TENANTID)

# ----------------------------------------------------------------------------
# Fichero: 04-observability.ps1 | Fecha: $($Dates["04-observability.ps1"])
# ----------------------------------------------------------------------------
# Connection string del recurso Application Insights.
APPLICATIONINSIGHTS_CONNECTION_STRING=$($Values.APPLICATIONINSIGHTS_CONNECTION_STRING)
ENABLE_OBSERVABILITY=$($Values.ENABLE_OBSERVABILITY)
# Exportador específico de Agent 365 (Frontier). En false usa rutas estándar/locales.
# Si tu tenant y flujo Agent 365 están operativos, cambia a true en fases posteriores.
ENABLE_A365_OBSERVABILITY_EXPORTER=$($Values.ENABLE_A365_OBSERVABILITY_EXPORTER)
# Nombre lógico del servicio en telemetría (service.name en OTel).
OTEL_SERVICE_NAME=$($Values.OTEL_SERVICE_NAME)
# Namespace lógico del servicio para separar dominios en observabilidad.
OTEL_SERVICE_NAMESPACE=$($Values.OTEL_SERVICE_NAMESPACE)

# ----------------------------------------------------------------------------
# Fichero: 05-webapp-m365.ps1 | Fecha: $($Dates["05-webapp-m365.ps1"])
# ----------------------------------------------------------------------------
# We Application
WEB_APP_NAME=$($Values.WEB_APP_NAME)
"@
}

function Update-EnvGeneratedSection {
    param(
        [string]$ScriptPath,
        [string]$SectionName,
        [hashtable]$SectionValues
    )

    $repoRoot = Get-RepoRootFromScriptPath -ScriptPath $ScriptPath
    $envPath = Join-Path $repoRoot ".env.generated"

    $state = Read-EnvGeneratedState -EnvPath $envPath
    $values = $state.Values
    $dates = $state.Dates

    foreach ($key in $SectionValues.Keys) {
        if ($values.Contains($key)) {
            $values[$key] = [string]$SectionValues[$key]
        }
    }

    $dates[$SectionName] = Get-EnvGeneratedDateStamp

    $content = ConvertTo-EnvGeneratedContent -Values $values -Dates $dates
    Set-Content -Path $envPath -Value $content -Encoding utf8

    return $envPath
}
