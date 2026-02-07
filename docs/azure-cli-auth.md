# Autenticación con Azure CLI

Guía de comandos de Azure CLI para gestionar autenticación en entornos con múltiples cuentas y tenants.

## Requisitos previos

1. **Azure CLI** instalado ([guía de instalación](https://docs.microsoft.com/cli/azure/install-azure-cli))
2. **Extensión ML** (necesaria para los scripts de infraestructura):
   ```powershell
   az extension add --name ml
   ```

## Comandos de login

### Login básico

```powershell
# Login interactivo (abre navegador)
az login

# Login a un tenant específico
az login --tenant <tenant-id-o-dominio>

# Ejemplos
az login --tenant contoso.onmicrosoft.com
az login --tenant xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

### Login con Service Principal (CI/CD)

```powershell
az login --service-principal \
    --username <client-id> \
    --password <client-secret> \
    --tenant <tenant-id>
```

## Ver cuentas y subscriptions

### Listar todas las cuentas disponibles

```powershell
az account list --output table
```

Salida ejemplo:
```
Name                          CloudName    SubscriptionId                        TenantId                              State    IsDefault
----------------------------  -----------  ------------------------------------  ------------------------------------  -------  ---------
Mi-Subscription-Lab           AzureCloud   xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy  Enabled  True
Produccion-Corporativo        AzureCloud   aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee  11111111-2222-3333-4444-555555555555  Enabled  False
```

### Ver cuenta activa actual

```powershell
# Formato tabla
az account show --output table

# Formato JSON (más detalle)
az account show

# Solo campos específicos
az account show --query "{Nombre:name, Tenant:tenantId, Usuario:user.name}" --output table
```

### Listar tenants disponibles

```powershell
az account tenant list --output table
```

## Cambiar entre cuentas

### Cambiar por nombre de subscription

```powershell
az account set --subscription "Mi-Subscription-Lab"
```

### Cambiar por subscription ID

```powershell
az account set --subscription "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

### Verificar el cambio

```powershell
az account show --query "{Nombre:name, Tenant:tenantId}" --output table
```

## Verificar identidad

### Ver usuario actual

```powershell
az ad signed-in-user show --query "{Nombre:displayName, Email:userPrincipalName}" --output table
```

### Ver token actual (debug)

```powershell
az account get-access-token --query "{Token:accessToken[0:50], Expira:expiresOn}" --output table
```

### Obtener token para un recurso específico

```powershell
# Token para Azure Management
az account get-access-token --resource https://management.azure.com/

# Token para Cognitive Services
az account get-access-token --resource https://cognitiveservices.azure.com/

# Token para Microsoft Graph
az account get-access-token --resource https://graph.microsoft.com/
```

## Cerrar sesión

```powershell
# Cerrar sesión de TODAS las cuentas
az logout

# Cerrar sesión de una cuenta específica
az logout --username admin@contoso.onmicrosoft.com

# Limpiar cache de tokens completamente
az account clear
```

## Escenarios del laboratorio

### Escenario 1: Crear infraestructura (requiere permisos elevados)

```powershell
# 1. Login como usuario con permisos de Contributor/Owner
az login --tenant <tenant-laboratorio>

# 2. Verificar cuenta
az account show --query "{Usuario:user.name, Subscription:name}" --output table

# 3. Ejecutar scripts de infraestructura
cd infra/scripts
.\deploy-all.ps1
```

### Escenario 2: Ejecutar código como usuario normal

```powershell
# 1. Cerrar sesión de admin (opcional)
az logout

# 2. Login como usuario de prueba
az login --tenant <tenant-laboratorio>

# 3. Verificar cuenta
az account show --query "{Usuario:user.name, Subscription:name}" --output table

# 4. Ejecutar código
cd platforms/foundry/01-simple-chat
python src/main.py
```

### Escenario 3: Cambiar entre tenant de lab y corporativo

```powershell
# Ver contexto actual
az account show --query "{Subscription:name, Tenant:tenantId}" --output table

# Cambiar al tenant de laboratorio
az account set --subscription "Mi-Subscription-Lab"

# Cambiar al tenant corporativo
az account set --subscription "Produccion-Corporativo"
```


## Resumen de comandos

| Acción | Comando |
|--------|---------|
| Login interactivo | `az login` |
| Login a tenant específico | `az login --tenant <tenant>` |
| Ver cuenta activa | `az account show` |
| Ver todas las cuentas | `az account list -o table` |
| Cambiar subscription | `az account set -s <name-o-id>` |
| Ver usuario actual | `az ad signed-in-user show` |
| Obtener token | `az account get-access-token` |
| Cerrar sesión | `az logout` |
| Limpiar cache | `az account clear` |

## Troubleshooting

### "AADSTS50076: Need to use multi-factor authentication"

```powershell
# Forzar login interactivo con MFA
az login --use-device-code
```

### "The subscription could not be found"

```powershell
# Refrescar lista de subscriptions
az account list --refresh --output table
```

### Token expirado

```powershell
# Re-autenticar
az login --tenant <tu-tenant>
```

### Verificar permisos en un recurso

```powershell
# Ver roles asignados
az role assignment list --assignee <tu-email> --output table
```
