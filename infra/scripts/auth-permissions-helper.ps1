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
        return @{ Ok = $true; Detail = "Azure CLI instalado (versión: $($azVersion.'azure-cli'))" }
    } catch {
        return @{ Ok = $false; Detail = "Azure CLI no está instalado. Instálalo desde: https://learn.microsoft.com/cli/azure/install-azure-cli" }
    }
}

function Ensure-AzureSession {
    param([hashtable]$CliCheck)

    if (-not $CliCheck.Ok) {
        return @{ Ok = $false; Detail = "No se puede validar sesión sin Azure CLI" }
    }

    $account = az account show --output json 2>$null | ConvertFrom-Json

    if (-not $account) {
        Write-Info "No hay sesión activa. Iniciando login..."
        az login --output none 1>$null 2>$null
        $account = az account show --output json | ConvertFrom-Json
    }

    if (-not $account) {
        return @{ Ok = $false; Detail = "No se pudo resolver la cuenta activa de Azure" }
    }

    if ($account.state -ne "Enabled") {
        return @{ Ok = $false; Detail = "La subscription activa no está habilitada (estado: $($account.state))" }
    }

    return @{
        Ok      = $true
        Detail  = "Sesión activa"
        Account = $account
    }
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

    $principalObjectId = Get-CurrentPrincipalObjectId -Account $Account
    if (-not $principalObjectId) {
        return @{
            ResourceRoleOk   = $false
            RoleAssignRoleOk = $false
            DetailResource   = "No se pudo resolver el objeto de identidad actual en Entra ID"
            DetailAssign     = "No se pudo resolver el objeto de identidad actual en Entra ID"
            SubscriptionScope = ""
        }
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
        return @{
            ResourceRoleOk   = $false
            RoleAssignRoleOk = $false
            DetailResource   = "No se encontraron asignaciones RBAC en la subscription activa"
            DetailAssign     = "No se encontraron asignaciones RBAC en la subscription activa"
            SubscriptionScope = $subscriptionScope
        }
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

    $detailResource = if ($hasResourceRole) {
        "RBAC despliegue OK (Owner/Contributor detectado)"
    } else {
        "Faltan permisos para crear/actualizar recursos (requiere Owner o Contributor)"
    }

    $detailAssign = if ($hasRoleAssignmentRole) {
        "RBAC asignación de roles OK (Owner/UAA/RBAC Admin detectado)"
    } else {
        "Faltan permisos para asignar roles administrados (requiere Owner, User Access Administrator o RBAC Admin)"
    }

    return @{
        ResourceRoleOk    = $hasResourceRole
        RoleAssignRoleOk  = $hasRoleAssignmentRole
        DetailResource    = $detailResource
        DetailAssign      = $detailAssign
        SubscriptionScope = $subscriptionScope
    }
}

function Test-EntraAppPermissions {
    az ad app list --top 1 --query "[0].appId" --output tsv 1>$null 2>$null
    if ($LASTEXITCODE -eq 0) {
        return @{ Ok = $true; Detail = "Permisos básicos de Entra ID para App Registration validados (az ad app list)" }
    }

    $directoryRolesRaw = az rest `
        --method get `
        --url "https://graph.microsoft.com/v1.0/me/memberOf/microsoft.graph.directoryRole?`$select=displayName" `
        --output json 2>$null

    if ($LASTEXITCODE -eq 0 -and $directoryRolesRaw) {
        try {
            $directoryRoles = $directoryRolesRaw | ConvertFrom-Json
            $roleNames = @($directoryRoles.value | ForEach-Object { $_.displayName } | Where-Object { $_ })

            $acceptedRoles = @(
                "Global Administrator",
                "Application Administrator",
                "Cloud Application Administrator"
            )

            $matchedRoles = @($roleNames | Where-Object { $acceptedRoles -contains $_ })
            if ($matchedRoles.Count -gt 0) {
                return @{ Ok = $true; Detail = "Permisos Entra validados por rol de directorio: $($matchedRoles -join ', ')" }
            }
        } catch {
        }
    }

    return @{ Ok = $false; Detail = "No puede consultar/gestionar App Registrations en Entra ID. Comprueba rol activo (Global/Application/Cloud Application Administrator), PIM y políticas Graph/consent." }
}

function Assert-InfraPrerequisites {
    param(
        [string]$ForScript = "infra",
        [bool]$ShowValidationSection = $true
    )

    if ($env:SKIP_INFRA_PREREQS -eq "1") {
        if ($script:SubscriptionId) {
            az account set --subscription $script:SubscriptionId --output none 1>$null 2>$null
        }

        $fastAccount = az account show --output json 2>$null | ConvertFrom-Json
        if (-not $fastAccount) {
            Write-Error "No hay sesión activa de Azure para continuar en modo rápido."
            exit 1
        }

        Write-Info "Validación de permisos omitida (modo deploy-all)."
        return $fastAccount
    }

    if ($ShowValidationSection) {
        Write-Host "`n$("="*60)" -ForegroundColor Cyan
        Write-Host " VALIDACIÓN DE PRERREQUISITOS" -ForegroundColor Cyan
        Write-Host $("="*60) -ForegroundColor Cyan
    }

    $cliCheck = Ensure-AzureCliInstalled
    if ($cliCheck.Ok) {
        Write-Success $cliCheck.Detail
    } else {
        Write-Error $cliCheck.Detail
    }

    if ($script:SubscriptionId) {
        Write-Step "Estableciendo subscription:"
        az account set --subscription $script:SubscriptionId --output none 1>$null 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Subscripción establecida en: $($script:SubscriptionId)"
        } else {
            Write-Error "No se pudo establecer la subscription '$($script:SubscriptionId)'"
            exit 1
        }
    }

    Write-Step "Verificando sesión de Azure..."
    $sessionCheck = Ensure-AzureSession -CliCheck $cliCheck
    if ($sessionCheck.Ok) {
        $account = $sessionCheck.Account
        Write-Success "Sesión activa"
        Write-Endpoint "Usuario" $account.user.name
        Write-Endpoint "Tenant" $account.tenantId
    } else {
        Write-Error "Sesión de Azure no válida"
        Write-Info $sessionCheck.Detail
        $account = $null
    }

    Write-Step "Validando permisos RBAC para despliegue de infraestructura..."
    if ($account) {
        $rbacCheck = Test-RequiredRbacRoles -Account $account
    } else {
        $rbacCheck = @{
            ResourceRoleOk    = $false
            RoleAssignRoleOk  = $false
            DetailResource    = "No evaluado por falta de sesión"
            DetailAssign      = "No evaluado por falta de sesión"
            SubscriptionScope = ""
        }
    }

    if ($rbacCheck.ResourceRoleOk) {
        Write-Success "Permisos RBAC de despliegue validados"
    } else {
        Write-Error "Permisos RBAC de despliegue insuficientes"
        Write-Info $rbacCheck.DetailResource
    }

    if ($ForScript -eq "05-webapp-m365.ps1") {
        if ($rbacCheck.RoleAssignRoleOk) {
            Write-Success "Permisos RBAC para asignación de roles validados"
        } else {
            Write-Error "Permisos RBAC para asignación de roles insuficientes"
            Write-Info $rbacCheck.DetailAssign
        }
    }

    Write-Step "Validando permisos de Entra ID para App Registration..."
    $entraCheck = Test-EntraAppPermissions

    if ($entraCheck.Ok) {
        Write-Success "Permisos de Entra ID para App Registration validados"
    } else {
        Write-Error "Permisos de Entra ID para App Registration insuficientes"
        Write-Info $entraCheck.Detail
    }

    $requiredChecks = @(
        @{ Name = "Azure CLI"; Ok = $cliCheck.Ok; Detail = $cliCheck.Detail },
        @{ Name = "Sesión Azure + subscription"; Ok = $sessionCheck.Ok; Detail = $sessionCheck.Detail }
    )

    if ($ForScript -eq "03-m365-service-principal.ps1") {
        $requiredChecks += @{ Name = "Entra App Registration"; Ok = $entraCheck.Ok; Detail = $entraCheck.Detail }
    }
    else {
        $requiredChecks += @{ Name = "RBAC despliegue (Owner/Contributor)"; Ok = $rbacCheck.ResourceRoleOk; Detail = $rbacCheck.DetailResource }
    }

    if ($ForScript -eq "05-webapp-m365.ps1") {
        $requiredChecks += @{ Name = "RBAC asignación de roles (Owner/UAA/RBAC Admin)"; Ok = $rbacCheck.RoleAssignRoleOk; Detail = $rbacCheck.DetailAssign }
    }

    $failedChecks = @($requiredChecks | Where-Object { -not $_.Ok })

    if ($failedChecks.Count -gt 0) {
        Write-Host "`n$("="*60)" -ForegroundColor Red
        Write-Host " VALIDACIÓN FALLIDA - EJECUCIÓN BLOQUEADA" -ForegroundColor Red
        Write-Host $("="*60) -ForegroundColor Red
        Write-Info "Faltan prerrequisitos para '$ForScript':"
        $failedChecks | ForEach-Object {
            Write-Host "    - $($_.Name)" -ForegroundColor Red
            Write-Info "Detalle: $($_.Detail)"
        }
        Write-Info "Corrige los permisos antes de ejecutar cambios de infraestructura."

        if ($rbacCheck.SubscriptionScope) {
            Write-Info "Ejemplo RBAC despliegue: az role assignment create --assignee <OBJETO_O_UPN> --role Contributor --scope $($rbacCheck.SubscriptionScope)"
            Write-Info "Ejemplo RBAC asignación: az role assignment create --assignee <OBJETO_O_UPN> --role \"User Access Administrator\" --scope $($rbacCheck.SubscriptionScope)"
        }
        exit 1
    }

    Write-Endpoint "Subscription ID" $account.id
    Write-Endpoint "Tenant" $account.tenantId

    return $account
}

if ($MyInvocation.InvocationName -ne ".") {
    $null = Assert-InfraPrerequisites -ForScript "auth-permissions-helper.ps1"
}
