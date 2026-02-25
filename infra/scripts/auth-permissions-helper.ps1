# ============================================================================
# auth-permissions-helper.ps1 - Helper de sesión y permisos para despliegue infra
# ============================================================================

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptPath\..\config\lab-config.ps1"

function Ensure-AzureCliInstalled {
    Write-Step "Verificando Azure CLI..."
    try {
        $azVersion = az version --output json | ConvertFrom-Json
        Write-Success "Azure CLI instalado (versión: $($azVersion.'azure-cli'))"
    } catch {
        Write-Error "Azure CLI no está instalado. Instálalo desde: https://learn.microsoft.com/cli/azure/install-azure-cli"
        exit 1
    }
}

function Ensure-AzureSession {
    Write-Step "Verificando sesión de Azure..."

    $account = az account show --output json 2>$null | ConvertFrom-Json

    if (-not $account) {
        Write-Info "No hay sesión activa. Iniciando login..."
        az login --output none
        $account = az account show --output json | ConvertFrom-Json
    }

    if ($script:SubscriptionId) {
        Write-Step "Estableciendo subscription: $($script:SubscriptionId)"
        az account set --subscription $script:SubscriptionId --output none
        $account = az account show --output json | ConvertFrom-Json
    }

    if (-not $account) {
        Write-Error "No se pudo resolver la cuenta activa de Azure"
        exit 1
    }

    if ($account.state -ne "Enabled") {
        Write-Error "La subscription activa no está habilitada (estado: $($account.state))"
        Write-Info "Selecciona una subscription habilitada con: az account set --subscription <SUBSCRIPTION_ID>"
        exit 1
    }

    Write-Success "Sesión activa"
    Write-Info "Usuario: $($account.user.name)"
    Write-Info "Tenant: $($account.tenantId)"

    return $account
}

function Get-CurrentPrincipalObjectId {
    param([pscustomobject]$Account)

    $principalType = $Account.user.type
    $principalName = $Account.user.name

    if ($principalType -eq "servicePrincipal") {
        $objectId = az ad sp show --id $principalName --query id --output tsv 2>$null
        if (-not $objectId) {
            $objectId = az ad sp list --filter "appId eq '$principalName'" --query "[0].id" --output tsv 2>$null
        }
        return $objectId
    }

    return az ad signed-in-user show --query id --output tsv 2>$null
}

function Test-RequiredRbacRoles {
    param([pscustomobject]$Account)

    Write-Step "Validando permisos RBAC para despliegue de infraestructura..."

    $principalObjectId = Get-CurrentPrincipalObjectId -Account $Account
    if (-not $principalObjectId) {
        Write-Error "No se pudo resolver el objeto de identidad actual en Entra ID"
        Write-Info "Confirma que tu cuenta puede consultar Entra ID y vuelve a ejecutar"
        exit 1
    }

    $subscriptionScope = "/subscriptions/$($Account.id)"

    $allAssignments = az role assignment list `
        --assignee-object-id $principalObjectId `
        --all `
        --output json 2>$null | ConvertFrom-Json

    $assignments = @($allAssignments | Where-Object {
            $_.scope -and $_.scope.ToLowerInvariant().StartsWith($subscriptionScope.ToLowerInvariant())
        })

    if (-not $assignments) {
        Write-Error "No se encontraron asignaciones RBAC para la identidad en la subscription activa"
        Write-Info "Necesitas al menos 'Contributor' para crear recursos"
        Write-Info "Y además 'Owner' o 'User Access Administrator' (o 'Role Based Access Control Administrator') para asignar roles en 05-webapp-m365.ps1"
        exit 1
    }

    $roleNames = @($assignments | ForEach-Object { $_.roleDefinitionName } | Where-Object { $_ } | Select-Object -Unique)

    $hasResourceRole = $false
    $resourceAllowedRoles = @("Owner", "Contributor")
    foreach ($role in $resourceAllowedRoles) {
        if ($roleNames -contains $role) {
            $hasResourceRole = $true
            break
        }
    }

    $hasRoleAssignmentRole = $false
    $roleAssignmentAllowedRoles = @("Owner", "User Access Administrator", "Role Based Access Control Administrator")
    foreach ($role in $roleAssignmentAllowedRoles) {
        if ($roleNames -contains $role) {
            $hasRoleAssignmentRole = $true
            break
        }
    }

    if (-not $hasResourceRole) {
        Write-Error "Faltan permisos para crear/actualizar recursos en Azure"
        Write-Info "Permiso mínimo recomendado: Contributor en la subscription o Resource Group objetivo"
        Write-Info "Asignación ejemplo: az role assignment create --assignee <OBJETO_O_UPN> --role Contributor --scope $subscriptionScope"
        exit 1
    }

    if (-not $hasRoleAssignmentRole) {
        Write-Error "Faltan permisos para asignar roles administrados (necesario en 05-webapp-m365.ps1)"
        Write-Info "Necesitas Owner, User Access Administrator o Role Based Access Control Administrator"
        Write-Info "Asignación ejemplo: az role assignment create --assignee <OBJETO_O_UPN> --role ""User Access Administrator"" --scope $subscriptionScope"
        exit 1
    }

    Write-Success "Permisos RBAC mínimos validados"
}

function Test-EntraAppPermissions {
    Write-Step "Validando permisos de Entra ID para App Registration (script 03)..."
    az ad app list --top 1 --query "[0].appId" --output tsv 1>$null 2>$null

    if ($LASTEXITCODE -ne 0) {
        Write-Error "La identidad actual no puede consultar/gestionar aplicaciones en Entra ID"
        Write-Info "Para ejecutar 03-m365-service-principal.ps1 necesitas permisos como 'Application Developer' o superiores"
        Write-Info "También puedes pedir a un administrador que ejecute el script 03 y te comparta las credenciales generadas"
        exit 1
    }

    Write-Success "Permisos básicos de Entra ID validados"
}

function Assert-InfraPrerequisites {
    param(
        [string]$ForScript = "infra"
    )

    Write-Host "`n$("="*60)" -ForegroundColor Magenta
    Write-Host " VALIDACIÓN PREVIA DE PERMISOS" -ForegroundColor Magenta
    Write-Host $("="*60) -ForegroundColor Magenta
    Write-Info "Script objetivo: $ForScript"

    Ensure-AzureCliInstalled
    $account = Ensure-AzureSession
    Test-RequiredRbacRoles -Account $account
    Test-EntraAppPermissions

    Write-Host "`n$("-"*60)" -ForegroundColor Gray
    Write-Host " CONTEXTO ACTIVO" -ForegroundColor Yellow
    Write-Host $("-"*60) -ForegroundColor Gray
    Write-Endpoint "Subscription ID" $account.id
    Write-Endpoint "Subscription Name" $account.name
    Write-Endpoint "Tenant" $account.tenantId
    Write-Endpoint "Región objetivo" $script:Location

    Write-Host "`n$("="*60)" -ForegroundColor Green
    Write-Host " VALIDACIÓN COMPLETADA" -ForegroundColor Green
    Write-Host $("="*60) -ForegroundColor Green
    Write-Host ""

    return $account
}

if ($MyInvocation.InvocationName -ne ".") {
    $null = Assert-InfraPrerequisites -ForScript "auth-permissions-helper.ps1"
}
