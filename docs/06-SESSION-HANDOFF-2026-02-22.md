# Session Handoff — 2026-02-22

Objetivo: transferir estado técnico completo a una nueva sesión de Copilot sin perder contexto operativo.

## Fase actual (referencia explícita al plan)

Fuente canónica: [01-PLAN-M365-AGENT365.md](01-PLAN-M365-AGENT365.md)

**Estado de fase:**
- Fase 0: completada
- Fase 1: completada
- Fase 2: completada
- **Fase actual: Fase 3 en progreso (sin cierre de fase)**

Interpretación operativa: se cerró la transición **Fase 2 → Fase 3** tras validación satisfactoria del runbook pre-Fase 3, pero la Fase 3 no está cerrada.

## Decisión Go/No-Go (actualización)

- **Fecha:** 2026-02-22
- **Decisión:** **GO Fase 3**
- **Base:** validaciones operativas reportadas como satisfactorias (CLI, runtime M365, pruebas de Playground y checks de tooling).
- **Siguiente foco:** completar objetivos pendientes de Fase 3 antes de avanzar a Fase 4.

## Estado real de objetivos Fase 3 (plan)

1. Crear/usar app registration + Azure Bot Service:
  - **Parcial** (app registration usada en local/dev; Azure Bot Service aún pendiente de implementación/publicación).
2. Configurar secretos/credenciales en entorno:
  - **Completado en local/dev** (`MICROSOFT_APP_ID`, `MICROSOFT_APP_PASSWORD`, `MICROSOFT_APP_TENANTID`, adapter con `MsalConnectionManager`).
3. Generar/adaptar manifest M365 Copilot y empaquetar `.zip`:
  - **Pendiente**.
4. Desplegar endpoint público (App Service/Container Apps u otro):
  - **Pendiente**.

Regla de continuidad: **no avanzar de fase** hasta completar 3 y 4.

## Artefactos canónicos a leer al iniciar nueva sesión

1. [01-PLAN-M365-AGENT365.md](01-PLAN-M365-AGENT365.md)
2. [02-GUIA-FLUJO-RUNTIME-M365.md](02-GUIA-FLUJO-RUNTIME-M365.md)
3. [03-RUNBOOK-PREFASE3-M365.md](03-RUNBOOK-PREFASE3-M365.md)
4. [04-RUNBOOK-FASE3-LOCAL-TUNEL-M365.md](04-RUNBOOK-FASE3-LOCAL-TUNEL-M365.md)
5. [05-DETALLE-CAMBIOS-FASE3-2026-02-22.md](05-DETALLE-CAMBIOS-FASE3-2026-02-22.md)
6. [README.md](../README.md)

## Decisiones cerradas (no reabrir salvo instrucción explícita)

- Autenticación Foundry en local/dev: **Entra ID only** (`AzureCliCredential`).
- Sin fallback automático a API key.
- Separación de canales: CLI y M365 runtime desacoplados sobre servicio común.
- Documentación y ejecución enfocadas en validación incremental antes de Fase 3.

## Estado técnico resumido

- CLI (`platforms/maf/01-simple-chat/main.py`): validado.
- Runtime M365 (`platforms/maf/01-simple-chat/main_m365.py`): autenticación de canal integrada con `MsalConnectionManager` y validada en local/túnel.
- Herramientas de terminal en VS Code:
  - `npm --version`: OK
  - `teamsapptester --version`: OK en terminal nueva tras ajuste de PATH del workspace.

## Riesgos abiertos relevantes

- Objetivo 3 pendiente (manifest Copilot `.zip`) bloquea cierre de Fase 3.
- Objetivo 4 pendiente (endpoint público publicado) bloquea cierre de Fase 3.
- Dependencia de consistencia de credenciales/tenant según entorno activo de `az login`.

## Próximo paso único recomendado

Completar objetivo 3 de [Fase 3](01-PLAN-M365-AGENT365.md):
- generar/adaptar manifest M365 Copilot y empaquetar `.zip` para validación.

**Definition of Done para cerrar Fase 3:**
- Objetivo 3 completado: manifest Copilot válido y empaquetado.
- Objetivo 4 completado: endpoint público desplegado y operativo.
- Prueba end-to-end en canal objetivo con endpoint publicado.
- No quedan pendientes críticos de autenticación/canal.

---

## Prompt semilla para nueva sesión (copiar/pegar)

```text
Quiero continuar este proyecto exactamente desde el estado actual.

Lee y usa como fuente canónica, en este orden:
1) docs/01-PLAN-M365-AGENT365.md
2) docs/02-GUIA-FLUJO-RUNTIME-M365.md
3) docs/03-RUNBOOK-PREFASE3-M365.md
4) README.md

Reglas:
- No rediseñar arquitectura ni reabrir decisiones cerradas (Entra ID-only, sin API key fallback).
- Continuar desde fase actual: Fase 3 en progreso (objetivos 3 y 4 pendientes).
- No avanzar a Fase 4 hasta cerrar Definition of Done de Fase 3.
- Primero dame resumen de entendimiento + plan corto de ejecución.
- Luego ejecuta únicamente el siguiente paso operativo para completar Fase 3 y valida con evidencia.
```

## Checklist rápido de arranque en nueva sesión

- Abrir terminal nueva en VS Code.
- Confirmar:
  - `npm --version`
  - `teamsapptester --version`
  - `az account show --output table`
- Revisar [04-RUNBOOK-FASE3-LOCAL-TUNEL-M365.md](04-RUNBOOK-FASE3-LOCAL-TUNEL-M365.md).
- Ejecutar siguiente tarea pendiente de Fase 3 (manifest `.zip` o despliegue endpoint público).
