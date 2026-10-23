# Tareas de implementación: HU-003 — Verificación de correo

## Contexto y límites

- Cambio: `hu003-verificacion-correo`.
- Trazabilidad: `PB-003 → HU-003 → CU-003 → RF-033 → RNF-017 → Sprint 3`.
- Almacén: OpenSpec + Engram; idioma documental: español profesional; identificadores de código: inglés.
- El límite autoritativo de esta sesión es **400 líneas modificadas por revisión/slice**. No usar el `600` preexistente de `openspec/config.yaml`, que pertenece a HU-004.
- No modificar HU-004/HU-005/HU-006, `openspec/config.yaml`, `openspec/project-context.md`, `.pi/`, `nul`, `docs/diagramas/Diagrama1.eapx`, commits ni pushes.
- No iniciar investigación externa/provider. Los gaps técnicos se confirman en el checkout o entorno durante la aplicación.

## Review Workload Forecast

| Field | Value |
| ------- | ------- |
| Estimated changed lines | 700–950 authored changed lines for the complete HU-003 flow (additions + deletions; excludes generated artifacts) |
| 400-line budget risk | High |
| Chained PRs recommended | Deferred; current slice is one bounded work unit |
| Suggested split | Current: Slice 1 backend core (280–380); later slices are deferred until an explicit task update and authority check |
| Delivery strategy | ask-on-risk |
| Chain strategy | Not applicable to the current Slice 1; revisit when deferred slices are authorized |

Decision needed before apply: No for the explicitly authorized backend-core Slice 1
Chained PRs recommended: No for the current bounded slice
Chain strategy: deferred
400-line budget risk: High for the complete HU-003, controlled for Slice 1

### Slice boundaries

1. **Slice 1 — Backend core, 280–380 líneas.** Modelos HU-003, settings aislados, política/generación/hash, repositorio transaccional, migración aditiva y tests unitarios/focused de emisión, expiración, consumo único, límites y rollback. Inicio: identidad existente sin tablas HU-003; fin: núcleo testeable sin endpoints ni UI; rollback: retirar únicamente los archivos nuevos del núcleo y la migración, sin tocar `usuario_global`, sesiones ni HU-004.

## Reglas de ejecución y evidencia

- Aplicar estrictamente **RED → GREEN → TRIANGULATE → REFACTOR** en cada unidad de comportamiento; cada fase debe conservar comando, resultado y archivos afectados.
- Runner backend: `.venv/Scripts/python.exe -m pytest backend/tests -q`; lint: `.venv/Scripts/python.exe -m ruff check backend/app backend/tests`; tipos: `.venv/Scripts/pyright.exe backend/app backend/tests`.
- Migración backend: `.venv/Scripts/python.exe -m alembic -c backend/alembic.ini upgrade head` contra PostgreSQL disponible. Las validaciones de superficies cliente y web quedan diferidas a una actualización posterior de tareas.
- Cada unidad registra test focalizado y resultado, evidencia runtime o `N/A` con razón, límite de rollback y conteo authored additions + deletions.
- Los tests y la documentación de evidencia permanecen con el comportamiento que verifican.

## Slice 1 — Backend core (primero)

### 1. Confirmaciones previas y seams RED

- [ ] Confirmar `git rev-parse --show-toplevel`, estado de submódulos, rama actual, `backend/alembic.ini`, head real de Alembic y archivos de modelos/repositorios en `backend/app/modules/identity`; registrar evidencia sin modificar archivos protegidos. <!-- sdd-owner: implementation -->
- [ ] Crear RED en `backend/tests/test_email_verification.py` para hash no reversible, token URL-safe, TTL de 7 días, no filtración y contratos de fake clock/generator/repository/notifier, sin implementar producción. <!-- sdd-owner: implementation -->
- [ ] Crear RED para emisión inicial, reemplazo/invalidez del token anterior, cuenta pendiente, cooldown, ventana de 24 horas, máximo de 3 reenvíos y fallo de persistencia; fijar explícitamente que el primer envío no consume reenvíos pero inicia cooldown. <!-- sdd-owner: implementation -->
- [ ] Crear RED para consumo válido, expirado, inválido, invalidado, consumido y dos consumos concurrentes, incluyendo una sola transición de `correo_verificado` y ausencia de sesión automática. <!-- sdd-owner: implementation -->

### 2. GREEN — modelo, migración y núcleo

- [ ] Implementar `backend/app/modules/identity/models.py` con `EmailVerificationState`/`EmailVerificationToken`, nombres y constraints del diseño, separado de `Invitacion` de HU-004; mantener los modelos existentes sin renombres. <!-- sdd-owner: implementation -->
- [ ] Implementar `backend/app/core/config.py` con `email_verification_ttl_days`, cooldown, máximo, enforcement, URL web, esquema app y settings Mailpit; validar rangos y no modificar `activation_ttl_days`. <!-- sdd-owner: implementation -->
- [ ] Crear `backend/app/modules/identity/email_verification.py` con generador seguro, hash SHA-256, DTO efímero, protocolos, reloj inyectable y política de emisión/consumo; el token crudo no sale del proceso de construcción del mensaje. <!-- sdd-owner: implementation -->
- [ ] Extender `backend/app/modules/identity/repository.py` con locks en orden usuario → estado/token, emisión transaccional, invalidación previa, contadores, consumo condicional y rollback; no exponer SQL ni estados internos al contrato público. <!-- sdd-owner: implementation -->
- [ ] Crear `backend/alembic/versions/0006_hu003_email_verification.py` usando el head confirmado, no asumir `0005` si el checkout muestra otra revisión; migración aditiva, sin backfill y downgrade explícito que no toque cuentas/sesiones/HU-004/HU-005. <!-- sdd-owner: implementation -->

### 3. TRIANGULATE — núcleo y persistencia

- [ ] Ejecutar y ajustar los tests focalizados de `backend/tests/test_email_verification.py` contra fakes y PostgreSQL cuando el caso requiera locks; verificar exactamente un consumo concurrente efectivo. <!-- sdd-owner: implementation -->
- [ ] Ejecutar upgrade de Alembic en una base de prueba y verificar tablas, PK/FK, índice parcial, checks y conservación de `usuario_global.correo_verificado`, sesiones y datos no relacionados. <!-- sdd-owner: implementation -->
- [ ] Ejecutar Ruff y Pyright sobre backend; registrar resultados reales, sin declarar PASS si una herramienta no está disponible. <!-- sdd-owner: implementation -->

### 4. REFACTOR — Slice 1

- [ ] Refactorizar solo después de GREEN/TRIANGULATE para eliminar duplicación, estabilizar interfaces y asegurar que imports, logs, excepciones y DTOs nunca contienen token crudo, contraseña, hash o secreto; repetir tests focalizados. <!-- sdd-owner: implementation -->
- [ ] Verificar el conteo authored del Slice 1 (≤400), listar archivos exactos, registrar runtime de migración o `N/A` si PostgreSQL/imagen no está disponible, y documentar rollback independiente de commit. <!-- sdd-owner: implementation -->

## Alcance diferido

Las superficies de API/login/Mailpit, cliente móvil, web, demo final y documentación de evidencia permanecen descritas en la propuesta y el diseño, pero no son tareas ejecutables de esta iteración. Se incorporarán mediante una actualización explícita de este archivo, con nueva comprobación de autoridad nativa y presupuesto antes de editar esas superficies.

## Acciones posteriores del parent

- [ ] Iniciar revisión acotada para la slice implementada y validar el resultado mediante el flujo nativo correspondiente. <!-- sdd-owner: parent -->
- [ ] Decidir antes de `sdd-apply` si `ask-on-risk` autoriza Slice 1 y, si se encadenan PRs, fijar `stacked-to-main` o `feature-branch-chain`; no seleccionar silenciosamente `size:exception`. <!-- sdd-owner: parent -->
- [ ] Confirmar que cada slice conserve ≤400 líneas o detenerse y elevar una decisión explícita si no existe una división honesta y cohesiva. <!-- sdd-owner: parent -->
