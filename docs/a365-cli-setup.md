# Instalacion y configuracion inicial de a365 CLI

## 1. Instalacion

### 1.1 Prerrequisitos (Windows)
- .NET SDK instalado (cubre `dotnet` y `dotnet tool`).
- Runtime ASP.NET Core 8.x (requerido por la CLI). Version recomendada: 8.0.x.
- PowerShell 7+ (o Windows PowerShell) con permisos de usuario para instalar herramientas globales.

### 1.2 Instalar runtime ASP.NET Core 8
Opcion rapida (usuario actual):
```powershell
$runtimeVersion = "8.0.10"
iwr https://dot.net/v1/dotnet-install.ps1 -OutFile "$env:TEMP\dotnet-install.ps1"
& "$env:TEMP\dotnet-install.ps1" -Runtime aspnetcore -Version $runtimeVersion -InstallDir "$env:USERPROFILE\.dotnet"
```
Verificar runtime:
```powershell
"Runtime en:" $env:USERPROFILE"\".dotnet\shared\Microsoft.AspNetCore.App"
Get-ChildItem "$env:USERPROFILE\.dotnet\shared\Microsoft.AspNetCore.App" | Select-Object Name
```

### 1.3 Definir variables de entorno (persistentes usuario)
Ejecutar una vez en PowerShell:
```powershell
$dot = "$env:USERPROFILE\.dotnet"
[Environment]::SetEnvironmentVariable('DOTNET_ROOT', $dot, 'User')
[Environment]::SetEnvironmentVariable('DOTNET_ROOTx86', $dot, 'User')
[Environment]::SetEnvironmentVariable('DOTNET_MULTILEVEL_LOOKUP', '0', 'User')
$uPath = [Environment]::GetEnvironmentVariable('Path','User')
$newPath = "$dot;$dot\tools;" + $uPath
[Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
```
Despues de esto, abre una nueva ventana de PowerShell (o reinicia VS Code) para que tome el PATH.

Verificacion rapida de entorno:
```powershell
echo $env:DOTNET_ROOT
dotnet --info
```

### 1.4 Instalar a365 CLI
```powershell
dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli --prerelease
```
Si ya estaba, actualizar:
```powershell
dotnet tool update --global Microsoft.Agents.A365.DevTools.Cli --prerelease
```

Verificar instalacion:
```powershell
dotnet tool list -g
$env:PATH = "$env:USERPROFILE\.dotnet;$env:USERPROFILE\.dotnet\tools;$env:PATH"  # por si la sesion no hereda PATH
DOTNET_MULTILEVEL_LOOKUP=0 DOTNET_ROOT="$env:USERPROFILE\.dotnet" DOTNET_ROOTx86="$env:USERPROFILE\.dotnet" a365 --version
```
Deberias ver la version de a365 (ej. `1.1.62-preview+...`).

## 2. Configuracion de a365
Basado en la guia oficial: https://learn.microsoft.com/en-us/microsoft-agent-365/developer/custom-client-app-registration

### 2.1 Registrar aplicacion en Microsoft Entra
1) Entra admin center: `https://entra.microsoft.com` > App registrations > New registration.
2) Nombre: algo descriptivo (ej. `a365-cli-app`).
3) Supported account types: Single tenant.
4) Redirect URI: Public client/native (mobile & desktop) `http://localhost:8400/`.
5) Registrar.

### 2.2 Establecer Redirect URI adicional (Broker)
1) En Overview copia `Application (client) ID` (lo usaras en `a365 config init`).
2) En Authentication (preview) > Add Redirect URI > Mobile and desktop apps: `ms-appx-web://Microsoft.AAD.BrokerPlugin/{client-id}` reemplazando `{client-id}`.
3) Guardar/Configure.

### 2.3 Permisos delegados requeridos (5)
Usar siempre permisos **Delegated** (no Application):
- Application.ReadWrite.All
- AgentIdentityBlueprint.ReadWrite.All (beta)
- AgentIdentityBlueprint.UpdateAuthProperties.All (beta)
- Directory.Read.All
- DelegatedPermissionGrant.ReadWrite.All

#### Opcion A: Portal (si ves permisos beta)
1) App registration > API permissions > Add a permission > Microsoft Graph > Delegated.
2) Agrega los 5 permisos anteriores.
3) Grant admin consent for <tenant>. Necesitas rol: Application Administrator (recomendado), Cloud Application Administrator o Global Administrator.


### 2.4 Inicializar configuracion con a365
Con el `Application (client) ID` del paso 2.2:
```powershell
a365 config init
```
Sigue el asistente (pegando el client ID). La herramienta validara permisos y consent.

### 2.5 Verificaciones y troubleshooting rapidos
- Validacion CLI:
```powershell
a365 config init  # debe mostrar "Custom client app validation successful"
```
- Errores comunes:
  - Permisos de tipo Application: eliminar y volver a agregar como Delegated.
  - Falta admin consent (Opcion A): pulsa Grant admin consent en portal.
  - Si usaste Opcion B (Graph API), no pulses Grant admin consent en portal; si lo hiciste, repite el POST/PATCH para restaurar permisos beta.
  - Client ID incorrecto: verifica en Overview el Application (client) ID (no el Object ID).

### 2.6 Buenas practicas
- Registro single-tenant.
- Solo permisos delegados listados.
- Auditoria periodica y retiro de la app cuando no se use.
- No compartas el client ID publicamente.

## 3. Resumen de comprobaciones
- `dotnet --info` muestra runtime 8.x bajo `%USERPROFILE%\.dotnet`.
- `a365 --version` responde.
- App registrada con redirect URI `http://localhost:8400/` y `ms-appx-web://Microsoft.AAD.BrokerPlugin/{client-id}`.
- Cinco permisos delegados presentes y con admin consent (segun metodo A o B).
- `a365 config init` valida exitosamente.
