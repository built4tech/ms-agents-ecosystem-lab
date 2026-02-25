# ============================================================================
# 02-foundry-maf.ps1 - Crear recurso Foundry (AIServices) + despliegue gpt-4o-mini
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
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  1) Crear/reutilizar recurso Foundry (AIServices)            " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  2) Habilitar allowProjectManagement                         " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  3) Crear/reutilizar proyecto de agentes                     " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  4) Desplegar/reutilizar modelo configurado                  " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host -NoNewline "║" -ForegroundColor Cyan; Write-Host -NoNewline "  5) Persistir variables en .env.generated                    " -ForegroundColor White; Write-Host "║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

$account = Assert-InfraPrerequisites -ForScript "02-foundry-maf.ps1"

$framework = "MAF"
$foundryName = $script:FoundryName

Write-Host "`n$("="*60)" -ForegroundColor Cyan
Write-Host " Proyecto $framework - CREACIÓN" -ForegroundColor Cyan
Write-Host $("="*60) -ForegroundColor Cyan

# Verificar Resource Group
$rgExists = az group exists --name $script:ResourceGroupName
if ($rgExists -eq "false") {
    Write-Error "El Resource Group '$($script:ResourceGroupName)' no existe"
    Write-Host "Ejecuta primero: .\01-resource-group.ps1" -ForegroundColor Yellow
    exit 1
}

# ============================================================================
# 1. Recurso Foundry (AIServices)
# ============================================================================
$accountBaseUrl = "https://management.azure.com/subscriptions/$($account.id)/resourceGroups/$($script:ResourceGroupName)/providers/Microsoft.CognitiveServices/accounts/$foundryName"

function Wait-AllowProjectManagementReady {
    param(
        [string]$AccountUrl,
        [int]$Retries = 12,
        [int]$DelaySeconds = 5
    )

    for ($i = 1; $i -le $Retries; $i++) {
        $allowFlag = az rest `
            --method get `
            --url $AccountUrl `
            --url-parameters api-version=2025-06-01 `
            --query "properties.allowProjectManagement" `
            --output tsv 2>$null

        if ($LASTEXITCODE -eq 0 -and "$allowFlag" -eq "true") {
            return $true
        }

        Start-Sleep -Seconds $DelaySeconds
    }

    return $false
}

Write-Step "Creando recurso Foundry (AIServices) '$foundryName'..."

$foundryExists = az cognitiveservices account show `
    --name $foundryName `
    --resource-group $script:ResourceGroupName `
    --output json 2>$null

if ($foundryExists) {
    Write-Success "Foundry '$foundryName' ya existe"
} else {
    az cognitiveservices account create `
        --name $foundryName `
        --resource-group $script:ResourceGroupName `
        --kind "AIServices" `
        --sku "S0" `
        --location $script:Location `
        --custom-domain $foundryName `
        --assign-identity `
        --output none

    Write-Success "Recurso Foundry creado"
}

# Habilitar gestión de proyectos (requerido para crear projects en el portal)
$allowProjectManagement = $false
try {
    $allowProjectManagement = az rest `
        --method get `
        --url $accountBaseUrl `
        --url-parameters api-version=2025-06-01 `
        --query "properties.allowProjectManagement" `
        --output tsv 2>$null
} catch {
    $allowProjectManagement = $false
}

if ($allowProjectManagement -ne $true) {
    Write-Step "Habilitando allowProjectManagement en '$foundryName'..."
    $accountPatch = @{ properties = @{ allowProjectManagement = $true } } | ConvertTo-Json -Compress
    $accountPatchFile = New-TemporaryFile
    Set-Content -Path $accountPatchFile -Value $accountPatch -Encoding utf8

    try {
        $patchOutput = az rest `
            --method patch `
            --url $accountBaseUrl `
            --url-parameters api-version=2025-06-01 `
            --headers "Content-Type=application/json" `
            --body @$accountPatchFile `
            --output none 2>&1 | Out-String

        if ($LASTEXITCODE -ne 0) {
            throw $patchOutput
        }

        Write-Success "allowProjectManagement habilitado"
    } catch {
        Write-Error "No se pudo habilitar allowProjectManagement ($($_.Exception.Message))"
        throw
    } finally {
        Remove-Item -Path $accountPatchFile -ErrorAction SilentlyContinue
    }
} else {
    Write-Step "Verificando allowProjectManagement en '$foundryName'..."
    Write-Success "allowProjectManagement ya está habilitado"
}

Write-Step "Verificando propagación de allowProjectManagement..."
$allowReady = Wait-AllowProjectManagementReady -AccountUrl $accountBaseUrl -Retries 12 -DelaySeconds 5
if (-not $allowReady) {
    Write-Error "allowProjectManagement no quedó disponible a tiempo"
    exit 1
}
Write-Success "allowProjectManagement confirmado"

$foundryInfo = az cognitiveservices account show `
    --name $foundryName `
    --resource-group $script:ResourceGroupName `
    --output json | ConvertFrom-Json

# ============================================================================
# ============================================================================
# 2. Proyecto para agentes (projects)
#    Necesario para usar la vista Project y Agents en el portal
# ============================================================================
$projectName = "$foundryName-project"
$projectApiVersion = "2025-06-01"
$projectBaseUrl = "$accountBaseUrl/projects/$projectName"

Write-Step "Creando proyecto de agentes '$projectName' en $foundryName..."

$projectExists = $null
try {
    $projectExists = az rest `
        --method get `
        --url $projectBaseUrl `
        --url-parameters api-version=$projectApiVersion `
        --output json 2>$null
} catch {
    $projectExists = $null
}

if ($projectExists) {
    Write-Success "Proyecto '$projectName' ya existe"
} else {
    $projectBody = @{ location = $script:Location; identity = @{ type = "SystemAssigned" }; properties = @{} } | ConvertTo-Json -Compress
    $projectBodyFile = New-TemporaryFile
    Set-Content -Path $projectBodyFile -Value $projectBody -Encoding utf8

    try {
        $projectCreated = $false

        for ($attempt = 1; $attempt -le 6; $attempt++) {
            $projectOutput = az rest `
                --method put `
                --url $projectBaseUrl `
                --url-parameters api-version=$projectApiVersion `
                --headers "Content-Type=application/json" `
                --body @$projectBodyFile `
                --output none 2>&1 | Out-String

            if ($LASTEXITCODE -eq 0) {
                $projectCreated = $true
                break
            }

            $isAllowPmPropagationIssue =
                ($projectOutput -match "allowProjectManagement") -and
                ($projectOutput -match "set to true")

            if ($isAllowPmPropagationIssue -and $attempt -lt 6) {
                Write-Info "allowProjectManagement aún propagando; reintento $attempt/6 en 10s..."
                Start-Sleep -Seconds 10
                continue
            }

            throw $projectOutput
        }

        if (-not $projectCreated) {
            throw "No se pudo crear el proyecto tras varios reintentos"
        }

        Write-Success "Proyecto de agentes creado"
    } catch {
        Write-Error "No se pudo crear el proyecto de agentes ($($_.Exception.Message))"
        throw
    } finally {
        Remove-Item -Path $projectBodyFile -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# 3. Desplegar modelo gpt-4o-mini en Foundry
# ============================================================================
Write-Step "Desplegando modelo $($script:ModelName) en $foundryName..."

$deploymentName = $script:ModelName

$deploymentExists = az cognitiveservices account deployment show `
    --name $foundryName `
    --resource-group $script:ResourceGroupName `
    --deployment-name $deploymentName `
    --output json 2>$null

if ($deploymentExists) {
    Write-Success "Deployment '$deploymentName' ya existe"
} else {
    az cognitiveservices account deployment create `
        --name $foundryName `
        --resource-group $script:ResourceGroupName `
        --deployment-name $deploymentName `
        --model-name $script:ModelName `
        --model-version $script:ModelVersion `
        --model-format "OpenAI" `
        --sku-capacity $script:ModelCapacity `
        --sku-name $script:ModelSku `
        --output none

    Write-Success "Modelo desplegado exitosamente"
}

$apiVersion = if ($script:ApiVersion) { $script:ApiVersion } else { "2024-10-21" }
$null = Update-EnvGeneratedSection -ScriptPath $scriptPath -SectionName "02-foundry-maf.ps1" -SectionValues @{
    ENDPOINT_API    = "https://$($foundryInfo.name).services.ai.azure.com"
    ENDPOINT_OPENAI = "https://$($foundryInfo.name).openai.azure.com"
    DEPLOYMENT_NAME = $deploymentName
    PROJECT_NAME    = $projectName
    API_VERSION     = $apiVersion
}

Write-Host "`n$('-'*60)" -ForegroundColor Gray
Write-Host " ACTUALIZACIÓN DE .env.generated" -ForegroundColor Yellow
Write-Host $('-'*60) -ForegroundColor Gray
Write-Endpoint "ENDPOINT_API" "https://$($foundryInfo.name).services.ai.azure.com"
Write-Endpoint "ENDPOINT_OPENAI" "https://$($foundryInfo.name).openai.azure.com"
Write-Endpoint "DEPLOYMENT_NAME" $deploymentName
Write-Endpoint "PROJECT_NAME" $projectName
Write-Endpoint "API_VERSION" $apiVersion
