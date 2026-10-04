# RoomForge — Plan maestro de desarrollo por fases y subfases

> **Propósito:** explicar de principio a fin qué se construirá, por qué, en qué orden, qué puede avanzar en paralelo y cómo se demostrará que funciona.
>
> **Naturaleza:** hoja de ruta de producto y ejecución propuesta. No es evidencia de implementación, no reemplaza el backlog académico ni autoriza automáticamente tareas OpenSpec. La existencia de este plan no garantiza completar todo el alcance en un mes.
>
> **Regla central:** las pruebas técnicas bloquean únicamente las funciones que dependen de ellas. No es necesario terminar AR, IA o blockchain para avanzar con infraestructura, usuarios, inmobiliarias, catálogo y precios.
>
> **Dónde está el estado vigente:** §1.4 es el cuadro histórico de integración (corte 2026-09-26) y se conserva congelado. El **estado actual por fase y la casilla de asignación** están en **§1.4.1**, y el registro de la última integración en **§1.4.2.ter** (PR #12, 2026-10-03).

## Índice

1. [Lectura, fuentes y estado de partida](#1-lectura-fuentes-y-estado-de-partida)
2. [Producto final y alcance](#2-producto-final-y-alcance)
3. [Stack y razones de elección](#3-stack-y-razones-de-elección)
4. [Arquitectura, datos y contratos compartidos](#4-arquitectura-datos-y-contratos-compartidos)
5. [Dependencias, paralelismo y organización](#5-dependencias-paralelismo-y-organización)
6. [F00 — Alinear alcance y recuperar contexto](#f00--alinear-alcance-y-recuperar-contexto)
7. [F01 — Infraestructura local con Docker y Floci](#f01--infraestructura-local-con-docker-y-floci)
8. [F02 — Base de aplicación, UX y automatización](#f02--base-de-aplicación-ux-y-automatización)
9. [F03 — Identidad, roles y SaaS multiinmobiliaria](#f03--identidad-roles-y-saas-multiinmobiliaria)
10. [F04 — Inmuebles, publicaciones y catálogo](#f04--inmuebles-publicaciones-y-catálogo)
11. [F05 — Mobiliario, precios y ofertas versionadas](#f05--mobiliario-precios-y-ofertas-versionadas)
12. [F06 — Modelo editable y recorrido en primera persona](#f06--modelo-editable-y-recorrido-en-primera-persona)
13. [F07 — Captura espacial con el teléfono](#f07--captura-espacial-con-el-teléfono)
14. [F08 — IA preentrenada para mobiliario](#f08--ia-preentrenada-para-mobiliario)
15. [F09 — Reservas y contrato inteligente](#f09--reservas-y-contrato-inteligente)
16. [F10 — Integración de las tres superficies](#f10--integración-de-las-tres-superficies)
17. [F11 — Despliegue real en AWS](#f11--despliegue-real-en-aws)
18. [F12 — Calidad, seguridad y recuperación](#f12--calidad-seguridad-y-recuperación)
19. [F13 — Evidencia académica, demostración y entrega](#f13--evidencia-académica-demostración-y-entrega)
20. [Decisiones abiertas y riesgos](#6-decisiones-abiertas-y-riesgos)
21. [Criterio de producto terminado y mejoras posteriores](#7-criterio-de-producto-terminado-y-mejoras-posteriores)

## 1. Lectura, fuentes y estado de partida

### 1.1 Qué significa cada estado

- **Acordado:** decisión explícita del usuario consolidada en la redefinición.
- **Propuesto:** recomendación técnica o de organización; debe seleccionarse antes de comprometer su implementación.
- **Pendiente:** falta una decisión o comprobación. Se indica qué parte bloquea.
- **Reportado:** existe evidencia en otro documento; no se volvió a ejecutar su comprobación al redactar este plan.
- **Por implementar:** resultado futuro; una casilla o tarea escrita no implica que exista código.

Las fases `F00`–`F13` y sus subfases son identificadores locales de este plan, no sustituyen PB, HU, CP ni GAP. Cada subfase describe entrada, acciones, salida y comprobación. Sus criterios son objetivos futuros, no resultados de pruebas.

### 1.2 Fuentes y precedencia

| Fuente | Uso en este plan |
|---|---|
| [Redefinición acordada](redefinicion-roomforge.md) | Reglas del producto, recomendaciones y decisiones todavía abiertas. |
| [Propuesta original](propuesta-roomforge-original.md) | Antecedente de captura y reconstrucción; diferencias deben reconciliarse, no borrarse. |
| [Guía actual del repositorio](../AGENTS.md) | Convenciones y repositorio único; verificar vigencia de afirmaciones históricas de implementación. |
| [Infraestructura local](../infra/README.md) | Procedimiento actual de PostgreSQL y Floci. |
| [Registro de infraestructura](../odd/tasks/local-infrastructure.md) | Evidencia reportada por el trabajo de otro chat, no reejecutada aquí. |
| [Infraestructura histórica](scrum/sprint-0-requerimientos/09-infraestructura.md) | Alternativas anteriores, entre ellas Meshroom y servicios administrados AWS. |
| [IDs y trazabilidad](sprint-0/ids-trazabilidad.md) | Referencia canónica para mapear los futuros cambios a documentación académica. |

Este plan se añade sin modificar las fuentes. Una contradicción debe registrarse y resolverse antes de depender de ella. No se declaran cerrados GAPs históricos por haber redactado una hoja de ruta.

### 1.3 Qué existe y qué no se debe suponer

El repositorio se organiza actualmente como un repositorio único, con carpetas normales para backend, panel y aplicaciones móviles. Las menciones a submódulos en registros anteriores son contexto histórico, no instrucciones actuales de trabajo.

La infraestructura local ya tiene configuración nueva: `infra/docker/compose.local.yml` y `infra/docker/local-env.example`. Su registro reporta PostgreSQL y Floci saludables, consulta SQL correcta, bucket creado/listado y mensaje SQS enviado/recibido. También reporta que se conservaron contenedores y volúmenes. **No se comprobó en esta redacción que sigan ejecutándose ahora.**

Esa evidencia cubre servicios de desarrollo, no API, panel, IA ni contratos. En el corte de integración, `origin/main` conserva `infra/docker/compose.postgres.yml`, mientras que el checkout local lo marca como eliminado; esta auditoría no resuelve esa diferencia. No restaurar archivos retirados por el reinicio ni revertir cambios locales sin autorización. El estado actual del código de producto se inspeccionará antes de cada trabajo; no se da por implementado porque lo afirme un README histórico.

### 1.4 Estado de integración comprobado (corte 2026-09-26)

> ⚠️ **Cuadro histórico, congelado.** Describe el estado al 2026-09-26 y no refleja lo integrado después. Para el estado vigente por fase y la asignación de responsables, ver §1.4.1.

**Criterio:** “Integrado” significa presente en `origin/main`, no solo escrito en un plan, probado en otra rama o existente como archivo sin seguimiento. Este corte usa `origin/main` en `b6a468a`; no usa el checkout local `main`, que está en `848f28c`, nueve commits detrás y con otros cambios locales. Los resultados reportados por tareas se distinguen de la integración y no se vuelven a presentar como pruebas ejecutadas en este corte.

| Fase / área | Estado al corte | Evidencia y límite |
|---|---|---|
| F00 — Alineación y plan | 🟡 Documentación local, no integrada | Este plan y varios registros de redefinición/tareas aparecen como archivos sin seguimiento en el checkout principal. Sirven para orientar el trabajo, no son código ni evidencia integrada. |
| F01 — Infraestructura local | 🟡 Parcial | `origin/main` conserva `infra/docker/compose.postgres.yml`. `compose.local.yml` y `local-env.example` están solo en el checkout local; la salud actual de PostgreSQL/Floci no se revalidó en este corte. |
| F02 — Base de aplicaciones y UX | 🟡 Parcial | `panel/staff-shell` está versionado. El shell Flutter de `apps/cliente_mobile` existe como archivos locales sin seguimiento en el worktree móvil; no está integrado. `apps/captura_mobile` conserva únicamente su README. |
| F03 — Identidad, roles y agencias | 🟡 Subconjunto backend integrado | `origin/main` incluye identidad/sesión de personal y la gestión de agencias: tabla `agency`, alta/listado e invitaciones a `agency_admin`. Migraciones `0003_agency_registry` y `0004_staff_invitation_pending_email_unique`. La ejecución real de estas migraciones contra PostgreSQL sigue sin verificarse. |
| F04 — Inmuebles, publicaciones y catálogo | ⬜ No integrado | No se encontraron API/modelos de catálogo o publicaciones en `origin/main`. `odd/tasks/cliente-catalog.md` es planificación local, no implementación. |
| F05 — Mobiliario, precios y ofertas | ⬜ No integrado | No hay cálculo autoritativo de cotización, ofertas versionadas ni selección comercial de muebles en `origin/main`. |
| F06–F08 — Modelo 3D, captura e IA | ⬜ No integrado | No se encontró visor/editor 3D, flujo AR de captura ni worker/modelo IA integrados. La estructura de captura y `worker3d` conserva solo documentación inicial. |
| F09 — Reservas y escrow | ⬜ No integrado | `contracts/` contiene solo README; no hay implementación Solidity/Hardhat ni API de reservas integrada. |
| F10 — Integración de superficies | ⬜ No integrado | No existe evidencia de recorrido extremo a extremo entre captura, publicación, catálogo, cotización y reserva. |
| F11 — Despliegue AWS | ⬜ No integrado | No se verificó despliegue de la aplicación en AWS. |
| F12 — Calidad, seguridad y recuperación | 🟡 Parcial | El backend integrado tiene pruebas, lint y tipos verificados; faltan la verificación PostgreSQL indicada en F03 y pruebas integradas entre superficies. Los resultados Flutter reportados para el shell local no significan que esté integrado. |
| F13 — Evidencia académica y entrega | 🟡 Parcial | Hay documentación y evidencia de unidades existentes; la demostración completa y sus evidencias integrales siguen pendientes. |

**Notas de interpretación:** el worktree móvil está en `b6a468a`, pero sus archivos Flutter sin seguimiento no pertenecen a `origin/main`; el plan local CC-01 reporta pruebas/build, no las reejecutadas aquí. `origin/main` está en `b6a468a` por la integración de AGENCY-2 (PR #3). Este cuadro es una instantánea: actualizarlo tras cada merge y conservar separados los estados integrado, local y pendiente.

### 1.4.1 Estado actual y asignación por fase (corte 2026-09-30; última actualización 2026-10-03, PR #12)

**Criterio:** este cuadro reemplaza a §1.4 para leer el estado de hoy y conserva aquel corte como fotografía histórica. Usa la línea `main` posterior a la integración de §1.4.2 (PR #5 `f44f1a3` más el merge `14cbfe6`), que ya contiene F01 (PR de infraestructura), F02 (PRs #6–#9), F03 (PR #10), el trabajo de catálogo, cotizaciones y reservas (PR #4), los registros pendientes de HU-007 y, desde el 2026-10-03, F04 en todas las superficies (PR #12 `6541b1a`, registro en §1.4.2.ter).

**Leyenda de estados**

- ✅ **Completa:** resultado observable presente en `main`, con evidencia enlazada en la misma fila.
- 🟡 **Parcial:** subconjunto verificable integrado; lo que falta queda enumerado en la misma fila.
- ⬜ **Pendiente:** sin implementación integrada.
- ☐ **Asignación libre:** casilla que un dev completa con su nombre al tomar la fase.

**Cómo se usa la casilla de asignación.** La columna *Asignación* de este cuadro y la línea `**Asignación:**` al inicio de cada fase son los únicos lugares donde se escribe un responsable. Se completan con el nombre del dev al empezar la fase, sin borrar el estado, la evidencia ni el historial de §1.4. Una fase ✅ no cierra GAPs históricos, no ejecuta casos de prueba académicos y no autoriza entrega.

| Fase | Depende de | Estado | Evidencia y límite | Asignación |
|---|---|---|---|---|
| F00 — Alcance y contexto | — | 🟡 Parcial | `docs/plan-maestro-roomforge.md`, `docs/redefinicion-roomforge.md` y `docs/propuesta-roomforge-original.md` están versionados. Confirmados COP con dos decimales, depósito fijo por inmueble, wallet externa y cadena limitada a Hardhat local. Siguen abiertos: unidades del depósito, destino del depósito aceptado, firma institucional, testnet y tolerancias AR (§6.1). | ☐ Libre |
| F01 — Infraestructura local | — | ✅ Completa | `infra/docker/compose.local.yml` con `postgres`, `floci`, `api` y `panel`; `infra/docker/init-local-resources.ps1` idempotente; persistencia tras reinicio y proxies verificados en `odd/tasks/f01-infrastructure-completion.md`. Límite: no existe worker que conectar y las apps móviles no corren en Compose. | ☐ Libre |
| F02 — Base, UX y automatización | F01 | ✅ Completa | `docs/api/f02-api-contract.md`; `docs/migrations/f02-migration-verification.md` (completo 2026-09-29: base vacía a `head` contra PostgreSQL real, actualización desde `0004` y R6 en `0011_reservation_chain_txns`); `docs/ux/f02-surface-map.md`; `.github/workflows/ci.yml` con jobs de backend, panel, app cliente y app de captura. Límite: la semántica de GitHub Actions no se validó con `actionlint` y la cobertura numérica sigue sin acordar. | ☐ Libre |
| F03 — Identidad, roles y agencias | F02 | ✅ Completa | Módulos `identity`, `customer_identity`, `customer_wallet` y `agencies`; migraciones `0001`–`0006`; invitaciones y activación/desactivación de agentes; sesión de personal en la app de captura sobre cookie `HttpOnly` + CSRF. Cierre en `odd/tasks/f03-identity-agencies.md` (PR #10, `b791340`). El único E2E del repositorio, que nunca se había corrido, detectó y cerró un defecto de restauración de sesión en este panel: ver §1.4.2.bis. F03.3 quedó cerrado con PR #12 (2026-10-03): aislamiento entre agencias verificado sobre todas las rutas de inmueble (otra agencia y `platform_admin` `403`, ID ajeno en la ruta propia `404` idéntico a inexistente, sesión real `401`, catálogo público transversal), matriz por actor en `docs/api/f04-publications-v1.md`; evidencia: suite backend 506 aprobadas / 3 omitidas, Ruff y Pyright limpios (F04C-T6). Límite: el cierre de F03.3 se ejecutó dentro de la unidad de F04 (`odd/tasks/f04-listings-completion.md`), no como unidad de F03 propia. | ☐ Libre |
| F04 — Inmuebles, publicaciones y catálogo | F03 | 🟡 Parcial, integrado | **Integrado en `main` en dos tandas:** backend con el commit `6cb8ea8` y todas las superficies con PR #12 (merge `6541b1a`, 2026-10-03, registro en §1.4.2.ter). F04.1 ✅ alta/edición de inmueble con propietario y validación; F04.3 ✅ borrador → en revisión → aprobación/rechazo con motivo → publicar/despublicar, con autorización server-owned e historial append-only; F04.4 ✅ API más catálogo público real en la app cliente (lista con filtros y «Cargar más», detalle con precio, opcionales y estados honestos). Con PR #12 se agregaron además el listado y la consulta de inmuebles para personal (`GET /api/v1/staff/agencies/{agency_id}/listings[/{listing_id}]`), la bandeja de revisión real del panel (pestañas «En revisión» y «Aprobados», aprobar/rechazar/publicar/retirar con confirmación), «Mis inmuebles» en la app de captura (borrador → envío a revisión, motivo del último rechazo) y el transporte de invitaciones solo para desarrollo que permite crear el primer administrador en el stack local. F04.2 ⬜ **diferida por decisión del usuario** (fotografías originales privadas). Límites: el rechazo desde el panel solo está cubierto por pruebas automáticas (no hubo recorrido manual); la verificación contra PostgreSQL sigue siendo sobre bases descartables, no en un entorno desplegado; sin E2E automatizado del recorrido agencia → cliente. Contrato en `docs/api/f04-publications-v1.md`; registros en `odd/tasks/f04-publications.md` y `odd/tasks/f04-{listings-completion,panel-review-queue,capture-drafts,client-catalog}.md`. | ☐ Libre |
| F05 — Mobiliario, precios y ofertas | F04 | 🟡 Parcial | F05.2–F05.4 ✅: aritmética `Decimal` exacta con dos decimales y `ROUND_HALF_UP`, `POST /api/v1/quotes` con snapshot inmutable, vencimiento a 15 minutos, invalidación por `offer_version` y límite de 10 solicitudes por IP por minuto. F05.1 🟡: `ListingExtra` con ID estable, nombre y precio, sin categoría, habitación, dimensiones/procedencia ni vínculo visual, y sin UI de selección. | ☐ Libre |
| F06 — Modelo editable y recorrido | F02 | ⬜ Pendiente | No hay visor ni editor integrados; `docs/spikes/` conserva bitácoras exploratorias, no implementación. | ☐ Libre |
| F07 — Captura espacial | F06 | ⬜ Pendiente | La app de captura sólo tiene el acceso de personal; no hay sesión ARCore, marcado de contornos, alturas ni borradores de escena. | ☐ Libre |
| F08 — IA preentrenada | F05, F06 | ⬜ Pendiente | `worker3d/` sólo contiene README; no hay detector, pesos, trabajos asíncronos ni confirmación de sugerencias. | ☐ Libre |
| F09 — Reservas y contrato inteligente | F05 | 🟡 Parcial | Módulo `reservations` con estados `pending`, `accepted`, `rejected`, `cancelled` y `expired`, plazo de decisión, clave de idempotencia, vencimiento, permiso EIP-712 y reconciliación de cadena; migraciones `0007`–`0011`; `contracts/` con `ReservationEscrow.sol`, `RoomForgeTestToken.sol` y pruebas Hardhat; wallet de cliente verificada con EIP-191. Límite: sólo Hardhat local (sin testnet ni fondos reales), sin UI de wallet ni de reserva, y sin política de confirmaciones cerrada. F09.7 ⬜. | ☐ Libre |
| F10 — Integración de superficies | F03–F09 | 🟡 Parcial | Con PR #12 existen los primeros recorridos manuales entre superficies, integrados y registrados: agente en la app de captura hasta ver su inmueble en la bandeja del panel (`odd/tasks/f04-capture-drafts.md`) e inmueble publicado desde el panel visible en el catálogo de la app cliente (`odd/tasks/f04-client-catalog.md`), ambos en emulador contra la API real del stack local. Límite: no hay E2E automatizado entre superficies y el recorrido completo (cotización, reserva, wallet y contrato) sigue sin implementarse de punta a punta. | ☐ Libre |
| F11 — Despliegue en AWS | F02 | ⬜ Pendiente | No se verificó despliegue en AWS; sólo existe el stack local con Floci. | ☐ Libre |
| F12 — Calidad, seguridad y recuperación | transversal | 🟡 Parcial | CI con cuatro jobs en verde, suite backend más Flutter/panel, Pyright y Ruff sin diagnósticos nuevos frente a la línea base, y verificación real de la cadena de migraciones contra PostgreSQL. Límite: faltan pruebas integradas entre superficies, E2E de la trayectoria crítica, matriz de los siete criterios con mediciones y ensayo de fallos. | ☐ Libre |
| F13 — Evidencia académica y entrega | F12 | 🟡 Parcial | `docs/avance/` registra seis historias con verificación técnica y mantiene los casos académicos pendientes visibles; CP-001 y CP-002 cuentan con evidencia en `docs/scrum/sprint-1/evidencia/`. Límite: sin guion de demostración, sin evidencia integral y sin inventario final de recursos. | ☐ Libre |

**Nota de interpretación:** F03 en el cuadro histórico de §1.4 figura como subconjunto backend, F04–F05 y F09 como no integrados y F02 como parcial; esas filas describen el corte de 2026-09-26 y no deben leerse como estado actual. Actualizar este cuadro tras cada merge y conservar §1.4 sin ediciones.

### 1.4.2 Integración de registros pendientes (2026-09-30)

**Qué se integró.** Antes de este cierre, `main` estaba en `7e23ccb` y quedaban ramas con contenido fuera de la línea principal. La auditoría del 2026-09-30 las resolvió así:

| Elemento | Resolución |
|---|---|
| PR #5 `docs/hu007-evidence-and-pending-records` (3 commits, 15 archivos, +1294/−17) | Fusionado en `main` con `gh pr merge 5 --merge --admin`, merge commit `f44f1a3`. Aporta la evidencia de HU-007, el cambio OpenSpec `openspec/changes/hu022-025-publicaciones/` y `odd/references/saas-staff-login-v1.zip`. |
| `feat/roomforge-mobile-3d` (`94d30b1`, 1 commit de documentación) | Fusionado con `git merge --no-ff`, merge commit `14cbfe6`. Sólo actualiza el registro de promoción del PR #4 en `odd/tasks/cliente-catalog.md`. |
| `feat/registro-cliente/t3-identity` (`404fd97`) | **Descartada y borrada** en local y en `origin`. Su único commit modificaba `backend/app/modules/identity/repository.py`, archivo que no existe en `main`; el merge conflictuaba y el contenido quedó obsoleto con el reinicio de identidad. |
| Worktrees `f01-infrastructure-wt`, `f02-base-ux-automation-wt` y `f02-ci-review-wt` | Eliminados. Sus HEAD (`b8a07e3`, `f412f78`, `8002648`) ya estaban contenidos en `main` y no tenían cambios pendientes. |

**Qué queda fuera a propósito.** Las ramas `split-backend`, `split-captura`, `split-cliente`, `split-panel` y los remotos `backend-repo`, `captura-repo`, `cliente-repo` y `frontend-repo` pertenecen al experimento de separación por submódulos, abandonado: el proyecto se mantiene como repositorio único (§1.3) y esas ramas no aportan contenido que deba entrar en `main`. Se eliminaron del clon el 2026-09-30, después de verificar que su historial sigue publicado en los repositorios `sw1_pro_final_{backend,captura_mobile,cliente_mobile,frontend}_2026_2` de GitHub: `split-backend` `9ca516e`, `split-captura` `9acce4d`, `split-cliente` `3d27dd0` y `split-panel` `d836284`, los cuatro con el mismo commit final `docs(repo): link product repos and update per-app readmes`. El clon quedó con un solo remoto (`origin`) y sin ramas fuera de `main`. Los worktrees `proyecto_final-roomforge-mobile-3d-wt` y `roomforge-agency-management` se eliminaron el mismo día, junto con el directorio residual `proyecto_final-f02-base-ux-automation-wt`, que había quedado en disco tras la baja administrativa de git. Hoy el repositorio tiene un único worktree: el principal. La eliminación del worktree grande necesitó `robocopy /MIR` desde un directorio vacío porque Windows rechazaba los borrados por la ruta de más de 260 caracteres de los artefactos de Flutter.

**Nota de método.** El merge del PR #5 usó `--admin` y, por lo tanto, **salteó la regla de una aprobación** configurada en `main`; el propietario es administrador y `enforce_admins` está desactivado. Es el mismo procedimiento registrado para el PR #4 y se declara aquí para que esta evidencia no sugiera una revisión que no ocurrió.

### 1.4.2.bis Capturas, E2E y un defecto de restauración de sesión (2026-10-01)

El único E2E del repositorio (`panel/staff-shell/e2e/staff-login.e2e.test.mjs`) **nunca se había corrido**: el registro de F03 lo declaró explícitamente como "not run". Al correrlo detectó un defecto real en el panel:

- `ProtectedStaffShell` restauraba la sesión por una ruta sin guarda de single-flight, mientras el guard existía solo en una función hermana que el shell no llamaba; el cuerpo estaba duplicado entre ambas.
- Con `<StrictMode>`, React monta el efecto dos veces: la primera restauración rotaba el token (`200`) y la segunda recibía `401`, y el componente vivo descartaba una sesión válida y mostraba el login.
- Corregido moviendo el guard a la ruta que usa el shell y eliminando el cuerpo duplicado. El E2E quedó verde: `login, TOTP, /me, reload/restore, logout/revocation, and auth/CSRF negatives`.

La misma corrida produce las capturas de `docs/capturas/` (cinco PNG del panel que evidencian F02 y F03) y se agregó un E2E de F04 contra PostgreSQL descartable que aplica la cadena completa de migraciones y verifica `alembic current` = `0012_listing_transitions (head)`.

**Límites de esta unidad.** Las dos capturas del panel protegido (antes y después del reload) son **byte-idénticas**, porque la UI restaurada es exactamente la misma: la evidencia de la restauración es la aserción del E2E, no el píxel. La captura de la documentación de la API de F04 **no se pudo producir** (Swagger UI no renderizó la ruta) y no se inventó ninguna imagen. Las apps móviles no tienen capturas por falta de dispositivo o emulador. Los cinco PNG suman ~1,6 MB (a escala 1x; a 2x eran ~4,8 MB), y el E2E los reescribe en `docs/capturas/` en cada corrida salvo que se cambie `ROOMFORGE_CAPTURE_DIR`.

### 1.4.2.ter Integración de F04 en todas las superficies (PR #12, 2026-10-03)

**Qué se integró.** La rama `feat/f04-listings-completion` (10 commits) entró a `main` como PR #12, merge commit `6541b1a`. Entregó cuatro unidades registradas en `odd/tasks/`, cada una con verificación propia:

| Unidad | Contenido | Verificación registrada |
|---|---|---|
| `f04-listings-completion.md` | Rutas de personal `GET /api/v1/staff/agencies/{agency_id}/listings` y `GET .../listings/{listing_id}`; transporte de invitaciones solo para desarrollo (`backend/app/core/dev_email.py`, activado por `STAFF_EMAIL_SENDER_FACTORY` en el stack local); aislamiento entre agencias de F03.3 verificado sobre las 9 rutas de inmueble (F04C-T6); PostgreSQL descartable re-ejecutado y extendido al listado y consulta de personal (F04C-T7) | Suite backend 506 aprobadas / 3 omitidas; Ruff y Pyright limpios |
| `f04-panel-review-queue.md` | Bandeja real del administrador de agencia en el panel: pestañas «En revisión» y «Aprobados», detalle con historial, aprobar/rechazar/publicar/retirar con confirmación | `npm test` 97/97, build sin errores, revisión manual de aprobar → publicar → retirar (el rechazo solo por pruebas automáticas) |
| `f04-capture-drafts.md` | «Mis inmuebles» en la app de captura contra la API: lista por estado, ficha con validación equivalente, guardar borrador, envío a revisión, motivo del último rechazo; incluye la corrección del chequeo de `Origin` para clientes nativos (`f03-capture-staff-origin.md`) | `flutter test` 77/77, `flutter analyze` sin hallazgos, recorrido manual en emulador hasta ver el inmueble en la bandeja del panel |
| `f04-client-catalog.md` | Catálogo público real de F04.4 en la app cliente: lista con filtros y «Cargar más», detalle con precio base y periodicidad, opcionales, estados honestos de recorrido 3D y disponibilidad | `flutter test` 77/77, `flutter analyze` sin hallazgos, recorrido manual en emulador con un inmueble publicado desde el panel |

**Límites de esta integración.** El merge de PR #12 no volvió a ejecutar las suites: la evidencia citada es la registrada por cada unidad en su rama, más los cinco checks de CI del PR en verde al momento del merge (backend, panel, app cliente, app de captura). Los casos académicos CP-009 a CP-012 siguen sin ejecutar y no se acreditan con estos registros.

### 1.4.3 Fuentes canónicas y material no canónico

**Regla (2026-09-30, decisión del usuario):** las únicas fuentes canónicas de requisitos son [`redefinicion-roomforge.md`](redefinicion-roomforge.md) y este plan maestro. Ningún artefacto de `openspec/changes/` se usa como requisito de implementación ni como autoridad de alcance; sirve, a lo sumo, como registro histórico de una planificación anterior.

| Material | Estado | Verificación (2026-09-30) |
|---|---|---|
| `openspec/changes/hu022-025-publicaciones/` | **No canónico, no se usa.** Se registra porque el 2026-09-30 se había asociado a F04.1–F04.3 por error. | Describe un módulo `publications` y la migración `0010_hu006_publication_revisions.py` que no existen en este repositorio, más un guard de suscripción de HU-006 que tampoco existe. `git ls-files backend | grep -i public` no devuelve nada; `git log --all --diff-filter=A -- backend/app/modules/publications/models.py` está vacío; la migración 0010 real es `0010_reservations.py`; `openspec/specs/` no existe. |

**Qué dicen las dos fuentes canónicas sobre F04**, para trazabilidad de la implementación:

- Redefinición, actores: el **agente** prepara borradores; el **administrador de agencia** administra el contenido de su agencia y aprueba o rechaza las publicaciones preparadas por agentes. El aislamiento multi-tenant protege datos privados y operaciones administrativas, y el catálogo aprobado es visible entre agencias.
- Redefinición, publicaciones: el borrador **no aparece en el catálogo hasta la aprobación** de la agencia; **editar no debe reescribir la oferta asociada a una reserva ya aceptada** (se conserva la instantánea versionada de los datos comerciales); los estados de revisión incluyen la reapertura tras cambios.
- Plan, F04.1–F04.4: ficha del inmueble con propietario inmobiliario y validación de entradas; fotografías y privacidad; revisión y publicación con historial mínimo; catálogo y detalle del cliente.

El plan de trabajo de F04 vive en [`odd/tasks/f04-publications.md`](../odd/tasks/f04-publications.md).

### 1.4.4 Superficies por fase y reglas para trabajar en paralelo

**Para qué sirve.** La columna *Depende de* de §1.4.1 da el **orden mínimo**: una fase no arranca hasta que sus dependencias estén integradas en `main`. Esta sección agrega lo que de verdad evita que dos devs se pisen: **qué archivos toca cada fase**. El orden conceptual de §5.1 sigue vigente y no se duplica acá.

Las superficies son las rutas que existen hoy (corte 2026-09-30). Una fase que necesite una ruta nueva la declara antes de escribir.

| Fase | Superficie principal | Se cruza con |
|---|---|---|
| F00 | `docs/` (plan maestro y redefinición) | — |
| F01 | `infra/docker/*`, `infra/README.md`, `*/Dockerfile` | F11 (Dockerfiles) |
| F02 | `backend/app/{main.py,core/,db/}`, `backend/alembic/versions/`, `.github/workflows/ci.yml`, `docs/api/`, `docs/ci/`, `docs/ux/` | base de todas |
| F03 | `backend/app/modules/{identity,agencies,customer_identity}/`, `apps/cliente_mobile/lib/{data,domain}/`, `apps/captura_mobile/lib/{data,domain}/` | F07 y F09 (apps móviles) |
| F04 | `backend/app/modules/catalog/{router,schemas,service,models,errors}.py`, `backend/alembic/versions/`, `backend/tests/` | **F05: mismo módulo `catalog`** |
| F05 | `backend/app/modules/catalog/` (mobiliario y cotizaciones), `backend/alembic/versions/` | **F04: mismo módulo `catalog`** |
| F06 | módulo nuevo de visor/editor, `panel/staff-shell/src/features/`, `apps/*_mobile/lib/ui/` | F07 (contrato de escena), F10 (`panel`) |
| F07 | `apps/captura_mobile/lib/`, `apps/captura_mobile/android/` | F06 (contrato de escena), F03 (`captura_mobile`) |
| F08 | `worker3d/`, módulo nuevo de sugerencias y trabajos, `backend/alembic/versions/` | F04/F05/F09 (cadena de migraciones) |
| F09 | `backend/app/modules/reservations/`, `contracts/`, `apps/cliente_mobile/lib/` | F03 y F06 (app cliente) |
| F10 | todas las anteriores | **todas: no se paraleliza** |
| F11 | `infra/`, Dockerfiles, configuración de despliegue nueva | F01 (Dockerfiles) |
| F12 | `backend/tests/`, `.github/workflows/`, `docs/ci/` | todo lo que se prueba |
| F13 | `docs/`, `odd/tasks/`, evidencia académica | F12 |

**Reglas de convivencia**

1. **Una fila de la columna *Superficie principal* admite un dev a la vez.** F04 y F05 comparten `backend/app/modules/catalog/`: si van a tocarlo dos personas, coordinan antes de empezar o lo toma una sola.
2. **`backend/alembic/versions/` es recurso compartido.** Una migración nueva por rama, con `down_revision` sobre el head real del momento; verificar el head antes de crearla para que la cadena no se bifurque.
3. **Ramas separadas por fase.** Dos ramas que tocan el mismo módulo se integran de a una, no en paralelo.
4. **F10, F12 y F13 son transversales.** F10 no se paraleliza porque toca todas las superficies; cuando F12 o F13 estén activas, son el punto de coordinación antes de tocar `backend/tests/` y `docs/`.
5. **Excepciones de arranque anticipado ya declaradas en el plan**, y solo esas: F06 puede empezar con escenas sintéticas antes de F07; F08 puede empezar con el piloto de inferencia antes de F05/F06; F11 admite un smoke temprano después de F02.
6. **Contrato primero, código después.** Cuando dos fases comparten una interfaz, esa interfaz se congela y se documenta antes de que cada rama implemente, así ninguna espera a la otra. Interfaces conocidas: contrato de escena (F06 ↔ F07), sugerencias de IA (F08 ↔ F05/F06), oferta versionada (F04/F05 ↔ F09) y estado de publicación (F04 ↔ F10). El catálogo de contratos propuestos está en §4.3.
7. **Si dos ramas agregan migraciones, la segunda rebasa.** Al integrar la segunda, se cambia su `down_revision` al head nuevo, se vuelve a correr la migración en SQLite y recién entonces se integra. Nunca se reescribe una migración ya integrada en `main`.
8. **Una rama y un worktree por fase**, nombrados `feat/<fase>-<tema>` (por ejemplo `feat/f05-furniture-inventory`), partiendo de `main` actualizado. La rama se rebasa sobre `main` y se integra por fast-forward; no se hace merge entre ramas de features. Al cerrar, la rama se borra una vez contenida.
9. **Nadie espera a otra fase para empezar lo que no comparte.** Si dos fases solo comparten la cadena de migraciones, cada una avanza con su código y con un fixture propio; lo único que se serializa es la integración, no el desarrollo.

### 1.5 Restricciones

- Dos desarrolladores y un mes de plazo reportado; no se conocen horas efectivas diarias ni compromisos individuales.
- Minimizar gasto real. USD 100 de crédito AWS informado, pendiente de comprobar cobertura y vencimiento.
- Presentación final en AWS; Floci es emulación local, no reemplaza ese requisito.
- Teléfono de referencia: Samsung Galaxy S23 FE. No exigir detalles de variante para definir el plan.
- PC observada: Intel Core 5 120U, aproximadamente 16 GB RAM y gráficos Intel. Es información de hardware, no un benchmark del producto.
- Sin APIs pagadas de IA generativa. Usar modelos que ejecutemos nosotros, con licencia revisada.
- Documentación académica en español; código, identificadores y rutas HTTP públicas en inglés.
- No commits, push, cambios a EA ni borrado de volúmenes sin autorización correspondiente.

## 2. Producto final y alcance

### 2.1 Recorrido completo esperado

El administrador de plataforma registra una inmobiliaria y asigna su administrador. Este gestiona agentes. Un agente crea un inmueble, captura sus ambientes, prepara un modelo sencillo, confirma mobiliario y define una oferta. El administrador de la inmobiliaria revisa y publica.

Un cliente busca inmuebles, recorre el interior en primera persona, decide qué muebles opcionales incluir y ve el total actualizado. Con su billetera externa deposita tokens de prueba para reservar. La inmobiliaria responde; las reglas controlan aceptación, rechazo, cancelación pendiente y vencimiento. El cierre legal de venta o alquiler ocurre fuera del sistema y luego se registra su estado.

### 2.2 Funciones obligatorias acordadas

| Área | Alcance |
|---|---|
| Negocio | SaaS para varias inmobiliarias; venta y alquiler mensual. |
| Superficies | Panel web, app Android de captura y app del cliente. |
| Inmueble | Completo, de un solo piso, con varios ambientes conectados manualmente. |
| Representación | Geometría sencilla y editable; sin obligación de realismo fotográfico. |
| Recorrido | Movimiento libre en primera persona, no solo visitas por puntos. |
| Captura | Fotografías en el MVP; geometría estimada y corregible, método AR por validar. |
| Muebles | Inventario confirmado, selección comercial independiente de visibilidad 3D. |
| Precios | Base sin muebles opcionales; venta de pago único y alquiler con base y recargos mensuales. |
| Reserva | Depósito fijo por inmueble en tokens de prueba; billetera externa; retención en contrato. |
| Calidad | Siete criterios del docente con requisitos, pruebas y evidencia. |

### 2.3 Fuera del mínimo inicial

Video grabado y cargado solo si sobra tiempo. No exigir escaleras, varios pisos, VR, fotorealismo, reconstrucción total sin intervención humana, eliminación inteligente de muebles de fotografías, planos certificados, entrenamiento desde cero, suscripciones cobradas, compraventa legal en blockchain ni cobro mensual automatizado.

Excluir esas mejoras no permite eliminar funciones acordadas sin consultar. En particular, convertir el recorrido libre en puntos, sustituir toda captura por una escena ficticia o eliminar la app cliente sería un cambio de alcance, no una optimización técnica.

## 3. Stack y razones de elección

Todas las versiones concretas deben fijarse después de inspeccionar compatibilidad y archivos actuales. Mantener un stack documentado no equivale a afirmar que su implementación sobreviva al reinicio.

| Componente | Recomendación y función | Por qué frente a alternativas |
|---|---|---|
| API | FastAPI y Python, monolito modular | Encaja con la documentación y el ecosistema IA. Cambiar a Django o Node no aporta valor suficiente sin una razón concreta; no fragmentar en microservicios para dos personas. |
| Persistencia | PostgreSQL, SQLAlchemy y Alembic | Relaciones, transacciones y restricciones para negocio. JSONB puede alojar geometría flexible sin sustituir tablas comerciales. MongoDB no simplifica las reservas relacionales. |
| Panel | React, TypeScript y Vite | Formularios y editor web con tipos estáticos. No introducir Next.js solo por popularidad si no necesitamos sus capacidades de servidor. |
| Apps | Flutter y Dart | Separar captura y cliente, reutilizando convenciones. La parte AR necesita integración nativa Android; Flutter no garantiza portabilidad automática de esa función. |
| Captura | ARCore mediante plugin mantenido o módulo Kotlin | Aprovecha cámara y sensores del S23 FE. Evaluar API real y mantenimiento antes de elegir plugin. No enviar cada fotograma a Dart si basta devolver puntos y resultados. |
| Editor/visor | Three.js y TypeScript, WebView móvil como candidato | Compartir representación web/móvil; probar rendimiento y controles. Unity/native son alternativas si falla, pero añaden integración y herramientas. |
| IA | Detector pequeño preentrenado; PyTorch/Torchvision inicialmente; ONNX si conviene | Evita entrenamiento masivo. Exportar solo si funciona y mejora consumo; un runtime no sustituye pesos ni garantiza licencia. |
| Archivos | S3 real y Floci local | Separar fotos/binarios de datos transaccionales; acceso autorizado, no buckets públicos generales. |
| Trabajos | SQS y worker Python | Procesar sin bloquear peticiones. No añadir Celery, Redis o Kafka sin necesidad medida. |
| Blockchain | Solidity, componentes OpenZeppelin, Hardhat para desarrollo | Pruebas de reglas y tokens. Bibliotecas estándar reducen trabajo, no constituyen auditoría de seguridad. |
| Wallet | Externa, integración a seleccionar | El usuario firma; RoomForge no guarda su clave privada. Validar conexión móvil y retorno desde la billetera. |
| Local | Docker Compose y Floci | Reproducibilidad y bajo costo. Las apps corren en el teléfono; no son servidores dentro de Docker. |
| AWS | Comparar EC2/Compose con ECS/Fargate y RDS | EC2 puede simplificar demo, pero exige administración y backups; servicios administrados reducen operaciones con otro costo. No fijar ganador por intuición de precio. |
| CI | GitHub Actions | Ejecutar comprobaciones reproducibles. No desplegar automáticamente recursos con costo desde contribuciones no confiables. |

### 3.1 Qué cambia respecto de Meshroom

Fotogrametría y geometría paramétrica resuelven problemas distintos. Una malla de fotografías no identifica automáticamente habitaciones, muebles vendibles y paredes editables. Se recomienda que Meshroom deje de ser requisito del MVP y usar contornos/alturas para producir formas simples. Es una reconciliación pendiente con la propuesta original, no una afirmación de que Meshroom sea inútil.

### 3.2 Qué significa IA propia

La biblioteca ejecuta operaciones; la arquitectura define la red; los pesos contienen lo aprendido; el dataset contiene ejemplos. Inferencia aplica pesos; entrenamiento los modifica. Descargar pesos preentrenados permite inferencia sin descargar el dataset completo ni pagar una API de reconocimiento.

SSDLite320/MobileNetV3 con pesos COCO y YOLO11n son candidatos, no decisiones finales. Torchvision advierte revisar términos de pesos/datos; Ultralytics ofrece AGPL y Enterprise. Ejecutarlo en AWS no elimina obligaciones de licencia. No presentar integración de pesos ajenos como entrenamiento propio.

## 4. Arquitectura, datos y contratos compartidos

### 4.1 Responsabilidades

- **API:** autorización, reglas, precios, publicaciones, versiones, trabajos y seguimiento de reservas.
- **PostgreSQL:** identidades, pertenencias, inmuebles, reglas comerciales, estado durable y versiones.
- **S3:** fotografías y artefactos autorizados; acceso mediante mecanismos temporales/controlados.
- **Worker:** procesamiento de imágenes y generación de resultados; no decide precios ni privilegios.
- **Captura:** medición aproximada y borradores en el dispositivo.
- **Editor:** confirma estructura y muebles antes de publicar.
- **Visor:** representa escena y selección, sin ser autoridad comercial.
- **Contrato:** movimientos de tokens y transiciones on-chain permitidas.
- **Reconciliador:** contrasta eventos confirmados con el estado de la API, sin confiar en el éxito anunciado por el móvil.

### 4.2 Dominios iniciales

Definir usuarios, inmobiliarias, membresías/roles, inmuebles, publicaciones, habitaciones, aberturas, elementos de mobiliario, ofertas/versiones, reservas, referencias de transacciones, trabajos y archivos. Los nombres finales y tablas se fijan en el diseño de cada cambio; esta lista no es una migración autorizada.

Usar tipos decimales o enteros en unidades monetarias mínimas para precios, nunca flotantes binarios como autoridad. Validar unidades, moneda y periodicidad. El dinero comercial y el token de prueba no tienen conversión económica implícita.

### 4.3 Contratos que permiten trabajar en paralelo

| Contrato | Datos mínimos propuestos | Lo que independiza |
|---|---|---|
| Escena | Versión, unidad, habitaciones, contornos, altura/origen de medida, transformaciones, aberturas, objetos e identificadores | Visor y editor pueden avanzar con datos de prueba antes de terminar AR. |
| Sugerencia IA | Imagen, clase, caja 2D, puntuación, versión del modelo y estado de confirmación | Inventario manual funciona antes de la inferencia. |
| Oferta | Versión, inmueble, operación, moneda, base, opciones y total calculado | Precios se prueban sin billetera. |
| Trabajo | ID, propietario, entradas, versión, estado, intentos y resultado/error | Sincronización y consulta no dependen de duración del procesamiento. |
| Reserva | Oferta fijada, cliente, depósito, estado de negocio, estado on-chain y referencias | Se puede construir interfaz con fixtures explícitos sin fingir depósitos reales. |

Definir validación y migración del formato de escena. GLB, si se añade, será exportación o artefacto visual, no única fuente de reglas ni inventario. Cada dimensión debe conservar si proviene de AR, entrada manual o suposición; editarla no debe borrar silenciosamente su procedencia.

## 5. Dependencias, paralelismo y organización

### 5.1 Orden de dependencias, no barrera global

| Trabajo | Dependencia real | Puede avanzar sin |
|---|---|---|
| Infraestructura local | Docker y configuración segura | AR, IA, wallet y código de producto |
| Identidad y tenancy | Base API y PostgreSQL | Visor y blockchain |
| Catálogo/publicación | Tenancy y almacenamiento | Captura automática |
| Precios e inventario | Inmueble e identificación de objetos | Detector IA |
| Visor | Contrato de escena y prueba de renderizado | Escaneo real terminado |
| Captura AR | Dispositivo, integración AR y contrato de escena | Reserva |
| IA | Modelo/licencia y contrato de sugerencias | Precisión del plano |
| Reserva de negocio | Oferta versionada y estados acordados | Visor completo para pruebas de dominio |
| Escrow final | Regla de depósito cerrada, contrato/wallet validados | Detección IA |
| Publicación integral | Captura o edición válida, revisión y backend | Video opcional |
| Demostración final | Integración, evidencias y AWS | Funcionalidades explícitamente diferidas |

### 5.2 Dos líneas de trabajo propuestas

**Línea A:** infraestructura, API, tenancy, catálogo, precios, reservas, persistencia y AWS.

**Línea B:** interfaces, apps, contrato de escena junto con A, visor, captura e integración de sugerencias IA. Blockchain e IA necesitan revisión conjunta, no se asignan automáticamente a una persona por esta división.

Acordar responsables reales y evitar dos escritores sobre los mismos archivos. El paralelismo del plan no autoriza cambios concurrentes descoordinados. Integrar pequeñas trayectorias completas, no esperar que cada desarrollador termine todo su bloque aislado.

### 5.3 Ventana de un mes: orientación, no promesa

- **Primera parte:** confirmar baseline, infraestructura, API/roles y UX mínima; iniciar pruebas AR, visor, detector y wallet; primer smoke AWS pequeño.
- **Parte intermedia:** catálogo y precios utilizables; escena/visor y captura inicial; reglas de reserva e integración blockchain.
- **Última parte:** flujo integrado, correcciones, pruebas con usuarios, evidencia de calidad, despliegue consolidado y ensayo.

Reservar capacidad para integración y fallos. Si las mediciones muestran que no cabe, consultar recortes explícitos; no convertir funciones obligatorias en pantallas simuladas para marcar tareas completas.

### 5.4 Regla de trabajo por subfase

Antes de código sustancial, resolver requisitos y seguir el flujo SDD del proyecto mediante sus herramientas autorizadas: propuesta, especificación, diseño, tareas, aplicación, verificación y archivo. No crear resultados de fases no ejecutadas. Determinar el modo TDD real de la tarea sin inferirlo de la presencia de tests.

Al cerrar: registrar archivos y comportamiento, ejecutar comprobaciones pertinentes, documentar límites y actualizar trazabilidad. Solo declarar una subfase terminada cuando su resultado observable exista. Los gates siguientes son dependencias técnicas/producto, no aprobaciones inventadas de un controlador.

## F00 — Alinear alcance y recuperar contexto

**Objetivo:** evitar desarrollar contra documentación desactualizada. No convertir esta fase en semanas de planificación.

**Estado (corte 2026-09-30):** 🟡 Parcial — F00.1 ✅, F00.2 🟡, F00.3 🟡. Límite: siguen abiertas las decisiones de §6.1 y la trazabilidad a PB/HU/CP está registrada sólo de forma parcial en `docs/avance/`.
**Asignación:** ☐ Libre — escribir acá el responsable al tomar la fase.

### F00.1 — Inventario del estado actual

- **Entrada:** repositorio y documentos actuales; trabajo concurrente preservado.
- **Acciones:** revisar git, instrucciones, estructura real, manifiestos, cambios del reinicio y evidencias reportadas. Separar código disponible, plantilla y declaración histórica. No restaurar material eliminado automáticamente.
- **Salida:** mapa breve de superficies ejecutables y pendientes, con sus comandos realmente encontrados.
- **Aceptación:** otro integrante distingue qué puede arrancar y qué no; los estados no se basan solo en README antiguos.

### F00.2 — Decisiones mínimas y alcance

- **Acciones:** confirmar moneda, custodia empresarial/firma de aceptación, destino del depósito aceptado, ubicación de IA, límites geométricos y aceptación de testnet por el docente. No exigir resolver temas irrelevantes para la siguiente tarea.
- **Salida:** decisiones con alternativas, razón, responsable por asignar y módulo afectado.
- **Aceptación:** cada pendiente tiene un bloqueo localizado; ninguna ambigüedad comercial entra al contrato final como valor supuesto.

### F00.3 — Trazabilidad y backlog

- **Acciones:** confrontar redefinición con PB/HU/CP existentes; proponer actualización sin reciclar IDs ni cerrar GAPs por omisión. Conservar antecedentes y diferencias.
- **Salida:** mapa de cambios hacia historias y pruebas canónicas, más lista de discrepancias.
- **Aceptación:** cada funcionalidad comprometida tiene destino documental; las fases de este archivo no se confunden con sprints históricos.

## F01 — Infraestructura local con Docker y Floci

**Objetivo:** disponer de servicios reales de desarrollo desde el principio. Parte de este trabajo ya está reportada como realizada por otro chat.

**Estado (corte 2026-09-30):** ✅ Completa — F01.1 ✅, F01.2 ✅, F01.3 ✅, F01.4 ✅ (api y panel). Límite: no existe worker que conectar y las apps móviles siguen fuera de Compose.
**Asignación:** ☐ Libre — escribir acá el responsable al tomar la fase.

### Estado local y evidencia (2026-09-26)

F01-T1–T4 quedaron completadas localmente en la worktree `proyecto_final-f01-infrastructure-wt`, rama `feat/f01-infrastructure-completion`, basada inicialmente en `848f28c`. En el punto de verificación local anterior a la autorización de entrega, la rama todavía no tenía commits F01 ni estaba integrada en `origin/main`; esta nota conserva ese estado temporal y no modifica el corte histórico de integración de §1.4. La integración posterior se registra en la subsección siguiente. El registro de tarea y la evidencia detallada están en [F01 — infraestructura local](../odd/tasks/f01-infrastructure-completion.md).

- **F01-T1 — recursos locales:** `init-local-resources.ps1` crea únicamente el bucket y la cola configurados cuando faltan; se ejecutó dos veces y la segunda ejecución conservó los recursos existentes. Se usaron credenciales ficticias.
- **F01-T2 — Compose y salud:** el stack incluye `postgres`, `floci`, `api` y `panel`, con puertos configurables enlazados a loopback. La API usa PostgreSQL en `postgres:5432` y Floci en `http://floci:4566`; el proxy Vite del panel usa `api:8000` en Compose y conserva su valor por defecto de host. Los probes comprueban PostgreSQL, Floci, dependencias de API y respuesta HTTP de Vite; API espera a PostgreSQL/Floci saludables y panel a API saludable.
- **F01-T3 — verificación aislada:** en `roomforge-f01-verify` los cuatro servicios estuvieron saludables durante el smoke completo; el proxy del panel llegó a FastAPI y una ruta desconocida devolvió el 404 JSON esperado. El marcador PostgreSQL `f01-persist-20260926` sobrevivió el reinicio de PostgreSQL; el mensaje SQS del mismo nombre se recibió después del reinicio de Floci y se dejó sin borrar. El objeto S3 de 20 bytes `s3://roomforge-local-assets/f01/persistence-probe-20260926.txt` se descargó y coincidió con el marcador antes y después del reinicio de Floci, que volvió a `healthy`.
- **F01-T4 — documentación:** `infra/README.md` recoge el uso de los cuatro servicios, healthchecks, modo de bajo consumo, pruebas observadas y límites; este apartado del plan añade el resultado local y separa la integración posterior del corte histórico.

Al cierre de T3, los cuatro contenedores de prueba estaban detenidos; los volúmenes `roomforge-f01-verify_floci_data` y `roomforge-f01-verify_postgres_data` y sus datos se retuvieron intencionalmente, sin limpieza. `roomforge-local-dev` se observó detenido y no se operó; no se afirma que esté activo. Una medición puntual de Floci fue `38.37 MiB / 5.786 GiB`, no un objetivo ni una garantía.

**Límites de la evidencia:** no existe worker y las aplicaciones móviles quedan fuera de Compose. Floci emula S3/SQS localmente; no es AWS ni ofrece paridad completa. Los probes de API y las pruebas directas de persistencia no demuestran operaciones S3/SQS ejecutadas por la aplicación.

### Integración posterior al corte histórico de §1.4 (2026-09-26)

Después del corte documentado en §1.4, el trabajo F01 se integró en `origin/main` mediante el commit de trabajo `20919248ac53c76884e2037c7af6f9804c9b3f0e` (`feat(infra): complete local Docker and Floci stack`). La integración se confirmó por fast-forward de `b6a468a20888b5c3272fdea1d4815a27897232ba` a `af7345bed65c67f465fcd5fcfe36cd03adfd3dd3`; por tanto, la fila F01 de §1.4 permanece como fotografía histórica anterior y no como estado actual. El registro de tarea contiene los commits auxiliares, validaciones y límites de la entrega.

### F01.1 — Reutilizar el stack existente

- **Entrada:** [procedimiento de infraestructura](../infra/README.md) y su registro.
- **Acciones:** revisar configuración actual, puertos libres, estado de contenedores y volúmenes propios. Ejecutar el procedimiento documentado solo al trabajar en esta subfase, no por leer el plan.
- **Salida:** PostgreSQL y Floci accesibles; conservar nombre de proyecto y volúmenes dedicados.
- **Aceptación:** SQL responde y S3/SQS aceptan operaciones. El registro previo reporta estas pruebas; si se necesita estado actual, repetirlas sin destruir recursos ajenos.

### F01.2 — Recursos y configuración por entorno

- **Acciones:** definir nombres de bucket/colas, credenciales ficticias locales, endpoints y variables. Separar host, red Docker y teléfono: `localhost` dentro de cada uno no apunta al mismo lugar.
- **Salida:** configuración reproducible y creación idempotente de recursos propios.
- **Aceptación:** repetir preparación no duplica recursos inesperados; una configuración local no usa credenciales AWS reales. Variables privadas nunca se publican.

### F01.3 — Persistencia y parada segura

- **Acciones:** comprobar reinicio conservando datos y documentar stop/start. Si se hace prueba de restauración, usar destino temporal propio. No `down -v`, `prune` ni limpieza global.
- **Salida:** procedimiento de recuperación con límites conocidos.
- **Aceptación:** datos de prueba siguen disponibles tras reinicio; se conocen recursos persistentes y cómo detener cómputo sin borrar datos.

### F01.4 — Conectar progresivamente aplicaciones

- **Dependencia:** cada servicio debe tener código real ejecutable.
- **Acciones:** añadir API, web y luego worker cuando existan; healthchecks con significado, redes internas, puertos mínimos. No contenedores ficticios presentados como producto.
- **Salida:** Compose ampliado por cambios autorizados y reproducibles.
- **Aceptación:** API consulta PostgreSQL y accede a Floci; web consume API; las APK siguen ejecutándose en Android, no en Compose.

## F02 — Base de aplicación, UX y automatización

**Estado (corte 2026-09-30):** ✅ Completa — F02.1 ✅, F02.2 ✅, F02.3 ✅, F02.4 ✅, integrada por PRs #6–#9. Límite: sin validación de `actionlint` y sin cobertura numérica acordada.
**Asignación:** ☐ Libre — escribir acá el responsable al tomar la fase.

### F02.1 — Contrato API y estructura modular

- **Entrada:** baseline y configuración; no depende de AR.
- **Acciones:** definir módulos de dominio, validaciones, errores homogéneos, paginación y configuración. Rutas públicas en inglés, por ejemplo `/api/v1/listings`, como ejemplo no contrato aprobado.
- **Salida:** API mínima real, documentación de contrato y comprobación de disponibilidad.
- **Aceptación:** peticiones válidas/incorrectas tienen respuestas consistentes; errores internos no exponen secretos; operaciones lentas no bloquean solicitudes indefinidamente.

### F02.2 — Datos y migraciones

- **Acciones:** diseñar claves, restricciones, índices iniciales y unidades; migraciones explícitas. Crear base vacía y probar actualización desde versión anterior cuando exista.
- **Salida:** esquema versionado y datos de desarrollo identificados como ficticios.
- **Aceptación:** el mismo repositorio crea el esquema sin pasos ocultos; rollback o recuperación documentada, sin prometer que toda migración sea reversible.

### F02.3 — UX de las tres superficies

- **Acciones:** prototipar login, gestión, publicación, catálogo, selección y reserva. Mostrar carga, vacío, error, offline y permisos. Web adaptable; controles táctiles legibles, foco y contraste accesibles.
- **Salida:** mapa de pantallas y navegación, contratos de estado compartidos.
- **Aceptación:** recorridos revisados antes del detalle visual; ninguna operación irreversible depende de un botón sin confirmación/contexto.

### F02.4 — Pruebas y CI iniciales

- **Acciones:** fijar versiones según manifiestos reales, linters, tipos y runners. Ejecutar comprobaciones separadas por superficie. Proteger secretos y no desplegar recursos desde código no confiable.
- **Salida:** pipeline reproducible y procedimiento local equivalente.
- **Aceptación:** un defecto introducido en una comprobación provoca fallo visible; no se registra PASS si el runner no ejecutó tests. Cobertura numérica se acordará, no se inventa aquí.

## F03 — Identidad, roles y SaaS multiinmobiliaria

**Estado (corte 2026-09-30):** 🟡 Parcial — F03.1 ✅, F03.2 ✅, F03.3 🟡, F03.4 ✅. Límite: el criterio de catálogo público de F03.3 sigue sin re-verificarse contra el código de F04 ya integrado.

**Estado (corte 2026-10-03, PR #12):** ✅ Completa — F03.1 ✅, F03.2 ✅, F03.3 ✅, F03.4 ✅. F03.3 quedó cerrado dentro de la unidad de F04 (F04C-T6): aislamiento entre agencias verificado sobre las 9 rutas de inmueble con matriz por actor en `docs/api/f04-publications-v1.md`, y el catálogo público transversal entre agencias ya está probado y en uso por la app cliente. Límite: el cierre se ejecutó como tarea de F04 (`odd/tasks/f04-listings-completion.md`), no como unidad de F03 propia; la línea de estado anterior se conserva como fotografía del 2026-09-30.
**Asignación:** ☐ Libre — escribir acá el responsable al tomar la fase.

### F03.1 — Autenticación y sesiones

- **Entrada:** API/DB y decisión sobre reutilización real.
- **Acciones:** registro/login cliente, validación de datos, hash seguro de contraseñas, sesiones/expiración/logout y almacenamiento seguro de tokens en móvil. Revisar flujo de acceso staff sin asumir invitaciones ya implementadas.
- **Salida:** acceso funcional en apps/panel correspondientes.
- **Aceptación:** credenciales incorrectas, sesión expirada y logout producen comportamiento seguro; no mostrar contraseñas/tokens en logs. Reutilizar implementación previa solo si se verifica.

### F03.2 — Agencias y membresías

- **Acciones:** administrador de plataforma crea inmobiliaria y responsable; este gestiona agentes. Definir activación/baja y límites de pertenencia. Sin venta de suscripciones ni onboarding pagado en el MVP.
- **Salida:** relación usuario/agencia/rol validada en servidor.
- **Aceptación:** un agente no se autoasigna administrador; desactivar acceso impide nuevas operaciones protegidas según política acordada.

### F03.3 — Aislamiento y catálogo público

- **Acciones:** verificar dueño y permisos en cada operación; filtros de UI no son seguridad. Distinguir publicación pública de fotos originales/borradores privados.
- **Salida:** matriz de autorización por actor y pruebas de acceso cruzado.
- **Aceptación:** cambiar IDs no permite editar o leer datos privados ajenos; clientes sí consultan anuncios publicados de varias agencias.

### F03.4 — Integración de acceso

- **Acciones:** redirección por rol, recuperación de sesión, mensajes de acceso denegado y estados de red. Política de recuperación de cuenta por definir sin improvisar envío de correos inexistente.
- **Salida:** acceso usable en superficies reales.
- **Aceptación:** cerrar sesión evita reutilizar pantallas/cachés privadas y no requiere reiniciar la app.

## F04 — Inmuebles, publicaciones y catálogo

**Estado (corte 2026-09-30):** 🟡 Parcial, **integrado en `main`** con el commit `6cb8ea8` — F04.1 ✅, F04.2 ⬜ (diferida por decisión del usuario), F04.3 ✅, F04.4 ✅ en API y con UI pendiente. Evidencia: `backend/tests/test_f04_publications.py` (16 pruebas), suite backend 430 aprobadas / 2 omitidas, Ruff limpio y verificación independiente de 16 puntos que no encontró defectos de F04. Límites: la migración `0012_listing_transitions` se verificó contra un PostgreSQL descartable (cadena completa aplicada, `alembic current` = head), pero no en un entorno persistente; `pyright` mantiene 18 diagnósticos preexistentes en archivos no tocados (las dependencias sí están instaladas, causa sin explicar); sin UI. Los requisitos salen solo de la redefinición y de este plan (§1.4.3); el paquete `hu022-025-publicaciones` no se usa como fuente.

**Estado (corte 2026-10-03, PR #12):** 🟡 Parcial, **integrado en `main` en todas las superficies** — F04.1 ✅, F04.2 ⬜ (diferida), F04.3 ✅ con bandeja de revisión real en el panel, F04.4 ✅ con catálogo público real en la app cliente y rutas de personal para listar y consultar inmuebles. La línea de estado anterior se conserva como fotografía del 2026-09-30; el detalle de la integración está en §1.4.2.ter y en el párrafo siguiente.

**Avance integrado en `main` (PR #12, merge `6541b1a`, 2026-10-03):** en `feat/f04-listings-completion` se agregaron el listado paginado y filtrable (`GET /api/v1/staff/agencies/{agency_id}/listings`) y la consulta (`GET .../listings/{listing_id}`) de inmuebles para personal de la agencia, base de la bandeja de revisión del panel y de la lista de borradores de la app de captura, más un transporte de invitaciones solo para desarrollo que permite crear el primer administrador en el stack local. Evidencia: `test_f04_publications.py` 31 pruebas, suite backend 461 aprobadas / 3 omitidas, Ruff limpio y Pyright con 0 errores. Registro en `odd/tasks/f04-listings-completion.md`. En la misma rama, el panel reemplazó el prototipo de cola por la bandeja real del administrador de agencia (pestañas «En revisión» y «Aprobados», detalle con historial y aprobar/rechazar/publicar/retirar con confirmación) y el agente ve el aviso de continuar en la app de captura; evidencia: `npm test` 97/97, build sin errores y revisión manual de aprobar → publicar → retirar (el rechazo solo está cubierto por pruebas automáticas); registro en `odd/tasks/f04-panel-review-queue.md`. En la misma rama, la app de captura reemplazó los prototipos de F04 por «Mis inmuebles» contra la API (lista por estado, ficha con validación equivalente a la API, guardar borrador, envío a revisión con confirmación y motivo del último rechazo); el acceso nativo de personal requirió corregir el chequeo de `Origin` de F03 (`odd/tasks/f03-capture-staff-origin.md`). Evidencia: `flutter test` 77/77, `flutter analyze` sin hallazgos y recorrido manual en emulador con una cuenta de agente hasta verlo en la bandeja del panel; registro en `odd/tasks/f04-capture-drafts.md`. En la misma rama, la app cliente reemplazó el catálogo sintético por el catálogo público real de F04.4 (lista con filtros y «Cargar más», detalle con precio base y periodicidad, opcionales, y estados honestos de recorrido 3D y disponibilidad), y su manifiesto de depuración pasó a permitir HTTP local como la app de captura. Evidencia: `flutter test` 77/77, `flutter analyze` sin hallazgos y recorrido manual en emulador con un inmueble publicado desde el panel; registro en `odd/tasks/f04-client-catalog.md`. También en la rama, el aislamiento entre agencias de F03.3 se verificó sobre todas las rutas de inmueble (otra agencia y `platform_admin` `403`, ID ajeno en la ruta propia `404` idéntico a inexistente, sesión real `401`) y la matriz por actor quedó en `docs/api/f04-publications-v1.md`; evidencia: suite backend 506 aprobadas / 3 omitidas, Ruff y Pyright limpios, registro F04C-T6 en `odd/tasks/f04-listings-completion.md`. La prueba de F04 contra PostgreSQL 16 descartable se volvió a ejecutar en verde y se extendió al listado y la consulta de personal (orden, total, filtros y paginación sobre la base real); registro F04C-T7. El cuadro §1.4.1 y el registro de integración §1.4.2.ter quedaron actualizados con este merge.
**Asignación:** ☐ Libre — escribir acá el responsable al tomar la fase.

### F04.1 — Ficha del inmueble

- **Acciones:** guardar ubicación de búsqueda, operación, descripción, cantidad de ambientes/baños y atributos mínimos. Definir diferencia entre habitación del modelo y conteo comercial de dormitorios.
- **Salida:** alta/edición de inmueble con propietario inmobiliario.
- **Aceptación:** entradas inválidas se rechazan; no se inventa precisión geográfica ni se añaden mapas pagados como dependencia.

### F04.2 — Fotografías y privacidad

- **Acciones:** validar tipo/tamaño, permisos y claves de archivos; URLs temporales si corresponde. Separar pendiente/subido/confirmado y manejar subida fallida. Evitar personas o información personal en fotos de prueba; política de borrado/retención pendiente.
- **Salida:** imágenes asociadas al inmueble sin guardar binarios grandes en PostgreSQL.
- **Aceptación:** otra agencia no accede a originales privados; una subida incompleta no deja una publicación aparentemente terminada. Difuminado automático sería función adicional, no promesa asumida.

### F04.3 — Revisión y publicación

- **Acciones:** borrador por agente, envío a revisión, aprobación/rechazo con motivo, publicación y retiro. Definir si editar un publicado requiere nueva aprobación y mantener versión anterior mientras se revisa.
- **Salida:** flujo administrativo verificable con historial mínimo.
- **Aceptación:** cliente no ve borradores; agente no salta aprobación; cambio de publicación no reescribe una oferta reservada.

### F04.4 — Catálogo y detalle cliente

- **Acciones:** filtros ciudad/zona, venta/alquiler, precio base, habitaciones y baños; paginación y estados vacíos. Detalle aclara precio base y periodicidad, opcionales y estado de disponibilidad.
- **Salida:** búsqueda funcional sin depender del visor terminado.
- **Aceptación:** resultados coherentes con filtros y autorización; alquiler visible por mes, venta sin recargo mensual accidental. Si no hay modelo aún, mostrar estado honesto, no escena ajena.

## F05 — Mobiliario, precios y ofertas versionadas

**Estado (corte 2026-09-30):** 🟡 Parcial — F05.1 🟡, F05.2 ✅, F05.3 ✅, F05.4 ✅. Límite: falta el inventario de mobiliario con categoría, habitación, dimensiones/procedencia y vínculo visual, junto con su UI.
**Asignación:** ☐ Libre — escribir acá el responsable al tomar la fase.

### F05.1 — Inventario confirmado

- **Acciones:** crear objetos manualmente con ID estable, categoría, habitación, dimensiones/origen y vínculo visual. Separar detección IA no confirmada del inventario comercial.
- **Salida:** lista editable de mobiliario del inmueble.
- **Aceptación:** eliminar/reemplazar un objeto gestiona sus referencias; cantidades no se obtienen sumando detecciones de fotos repetidas.

### F05.2 — Reglas de precio

- **Acciones:** marcar opcionales, base sin opcionales y valor de cada elemento. Venta: base y extras de pago único. Alquiler: base mensual más extras mensuales. Validar moneda y redondeo acordados.
- **Salida:** cálculo centralizado con desglose.
- **Aceptación:** el servidor recalcula aunque el cliente altere el total; rechaza IDs ajenos, repetidos o no elegibles. Ocultar un objeto no cambia precio.

### F05.3 — Selección y cotización

- **Acciones:** cliente incluye/excluye opcionales; sincronizar lista y visor; indicar errores de disponibilidad. Definir vigencia de cotización y conflicto si cambia el anuncio.
- **Salida:** oferta versionada aceptable por reserva.
- **Aceptación:** total mensual = base mensual + recargos seleccionados; cotización vencida/cambiada exige nueva confirmación, no aceptación silenciosa.

### F05.4 — Instantánea del acuerdo

- **Acciones:** conservar precio, operación, moneda, elementos, versión y condiciones necesarias. Diferenciar escena editable actual de versión vinculada a oferta.
- **Salida:** datos inmutables consultables de la reserva.
- **Aceptación:** editar nombre/precio del sofá después no altera lo que el cliente había reservado; definir autorizaciones de lectura y retención.

## F06 — Modelo editable y recorrido en primera persona

**Estado (corte 2026-09-30):** ⬜ Pendiente — sin motor, visor ni editor integrados; `docs/spikes/` sólo conserva bitácoras exploratorias.
**Asignación:** ☐ Libre — escribir acá el responsable al tomar la fase.

**Inicio paralelo:** la prueba de renderizado puede comenzar con F02 y escenas sintéticas explícitas; no espera a F07.

### F06.1 — Probar motor e integración móvil

- **Acciones:** escena simple Three.js, WebView candidato, controles táctiles y navegación; medir consumo y fluidez en S23 FE. Comparar alternativa nativa solo si hay un problema concreto.
- **Salida:** elección fundamentada de motor/canal y límites medidos.
- **Aceptación:** carga y recuperación del visor funcionan; no se decide por captura de pantalla. Falla aquí bloquea el visor, no F03–F05.

### F06.2 — Generar escena paramétrica

- **Acciones:** convertir contorno/altura en suelo, paredes y techo; definir unidades, ejes, escala y transformaciones. Añadir aberturas transitables y muebles simples separados.
- **Salida:** escena reproducible desde datos estructurados.
- **Aceptación:** misma versión produce distribución consistente; rechazar contornos inválidos/intersecciones no soportadas. Una plantilla es plantilla, no captura real.

### F06.3 — Editor de correcciones

- **Acciones:** proponer editor web para mover/dimensionar objetos, corregir altura, ubicar puertas/ventanas y alinear habitaciones. Guardar borrador y publicar versión; confirmar ubicación final del editor antes de implementar.
- **Salida:** corrección manual sin tocar código ni JSON a mano.
- **Aceptación:** cambios persisten y se reflejan en el visor; puertas conectadas coinciden y las dimensiones estimadas/supuestas permanecen identificables.

### F06.4 — Navegación libre

- **Acciones:** cámara en primera persona, movimiento táctil, giro, colisiones básicas, límites y botón de retorno. Puertas abiertas transitables sin animaciones obligatorias; sin saltos ni física compleja.
- **Salida:** recorrido interior libre completo en un piso.
- **Aceptación:** no atravesar paredes o caer fuera de la escena; pasar entre habitaciones. Definir si muebles ocultos conservan colisión para evitar comportamiento sorprendente, independientemente de su selección comercial.

### F06.5 — Interacción comercial y carga segura

- **Acciones:** tocar objeto y ver nombre/precio/estado, sincronizar selección con API. Cargar únicamente contenido controlado; limitar puente WebView y evitar exponer tokens a páginas arbitrarias.
- **Salida:** recorrido conectado al inventario.
- **Aceptación:** objeto seleccionado corresponde al ID de oferta; un fallo de renderizado no modifica precios ni reserva. Lista accesible ofrece alternativa de selección sin reemplazar el recorrido requerido.

## F07 — Captura espacial con el teléfono

**Estado (corte 2026-09-30):** ⬜ Pendiente — la app de captura sólo tiene el acceso de personal; no hay sesión ARCore, contornos, alturas ni borradores de escena.
**Asignación:** ☐ Libre — escribir acá el responsable al tomar la fase.

**Alcance técnico por validar:** ARCore en S23 FE es compatible según fuente oficial, no significa medición exacta ni plano automático terminado.

### F07.1 — Integración AR y seguimiento

- **Entrada:** teléfono real, contrato de escena y permiso de cámara.
- **Acciones:** abrir sesión, detectar suelo, mostrar calidad/estado de seguimiento y errores; evaluar plugin mantenido o módulo Kotlin. Cámara en vivo no implica grabar video.
- **Salida:** puntos espaciales seleccionables con estado válido.
- **Aceptación:** pérdida de seguimiento se informa y no produce medidas ficticias; rechazo de permiso no bloquea toda la app.

### F07.2 — Contorno y dimensiones aproximadas

- **Acciones:** guiar marcado de esquinas, cerrar polígono y mostrar dimensiones estimadas. Validar forma, orden de puntos y autocruces; limitar formas soportadas explícitamente si hace falta.
- **Salida:** habitación editable generada desde observación real.
- **Aceptación:** guardar/reabrir conserva geometría; comparar con referencia independiente en evaluación. Sin referencia solo se afirma repetibilidad/interacción, no exactitud.

### F07.3 — Altura y aberturas

- **Acciones:** intentar referencia del techo si señal fiable; permitir altura supuesta editable si no la hay. Marcar procedencia y no confundir piso-techo con altura visual de cámara. Ubicar puertas/ventanas con ayuda manual.
- **Salida:** volumen cerrado y advertencias de estimación.
- **Aceptación:** no asignar valor silencioso como medición; superficies ocultas no se declaran observadas. El docente debe aceptar límites si exige captura automática completa.

### F07.4 — Varios ambientes

- **Acciones:** capturar ambientes separados, conservar referencia local y alinearlos manualmente mediante puertas/transformaciones. No prometer relocalización o unión automática.
- **Salida:** inmueble completo de un piso.
- **Aceptación:** continuidad de recorrido entre habitaciones, sin duplicación accidental de paredes/objetos ni escalas incompatibles.

### F07.5 — Borradores y sincronización

- **Acciones:** guardar fotos/escena en dispositivo, registrar pendientes, reintentar sin duplicar y mostrar progreso. Resolver edición local frente a remota mediante versión; controlar espacio y permitir limpiar solo datos propios confirmados.
- **Salida:** captura que sobrevive a cierre de app y pérdida de conexión.
- **Aceptación:** reconectar no crea dos inmuebles ni pierde capturas; reservar sigue requiriendo servicios/red. Inferencia offline es decisión separada.

## F08 — IA preentrenada para mobiliario

**Estado (corte 2026-09-30):** ⬜ Pendiente — `worker3d/` sólo contiene README; no hay detector, pesos, trabajos asíncronos ni confirmación de sugerencias.
**Asignación:** ☐ Libre — escribir acá el responsable al tomar la fase.

### F08.1 — Selección y licencia

- **Entrada:** categorías útiles y decisión de ubicación por resolver.
- **Acciones:** evaluar SSDLite/MobileNetV3 y alternativa YOLO pequeña. Revisar código, pesos y términos de datos. COCO incluye sillas, sofás, camas, mesas de comedor, TV y refrigeradores; no inferir puertas/ventanas o cualquier escritorio.
- **Salida:** ficha de candidato con licencia, clases y limitaciones.
- **Aceptación:** dependencia reproducible y permitida para la modalidad elegida; no comprar licencia ni contratar servicios sin autorización.

### F08.2 — Inferencia piloto sin entrenamiento

- **Acciones:** descargar pesos una vez, ejecutar imágenes con runtime local y obtener clases/cajas/puntuaciones. No descargar todo COCO ni pedir miles de fotos propias. 20–40 fotos autorizadas pueden servir como piloto exploratorio con revisión manual, no garantía estadística.
- **Salida:** ejemplos reales, latencia/memoria observadas y lista de errores.
- **Aceptación:** separar aciertos, falsos positivos y omisiones; puntuación no se vende como probabilidad calibrada. Dataset de evaluación no se reutiliza como prueba imparcial si se ajustó con él.

### F08.3 — Elegir ubicación y empaquetado

- **Acciones:** comparar teléfono offline contra worker en PC/AWS. Servidor simplifica actualización pero requiere sincronizar; móvil evita red pero compite con AR y aumenta integración. Confirmar cambio frente a IA offline original.
- **Salida:** decisión de ejecución; PyTorch inicial u ONNX tras validar operadores y resultados.
- **Aceptación:** conversión conserva comportamiento aceptable medido; ni benchmark ajeno ni tamaño de pesos se presenta como consumo total propio.

### F08.4 — Trabajos asíncronos si se elige servidor

- **Acciones:** API persiste trabajo, publica mensaje, worker descarga imagen autorizada y guarda resultado. Recuperar fallo entre persistir/encolar; limitar reintentos, visibilidad y trabajos fallidos. SQS puede entregar duplicados.
- **Salida:** estados pendientes/en curso/completados/fallidos y reintento controlado.
- **Aceptación:** duplicar mensaje no duplica inventario; reiniciar worker permite recuperación. Esta subfase se adapta si se elige móvil, no se impone nube por defecto.

### F08.5 — Confirmación humana e inventario

- **Acciones:** mostrar sugerencias, descartar/confirmar, identificar repetidos entre fotos y colocar formas en escena. El agente define dimensiones y precio; IA no inventa geometría métrica ni valor comercial.
- **Salida:** objetos confirmados enlazados a F05/F06.
- **Aceptación:** una detección errónea no se publica/vende sola; se puede completar inventario manualmente. Ajustar umbral no se registra como entrenamiento.

### F08.6 — Mejora opcional

- **Entrada:** errores registrados del piloto, licencia revisada y capacidad disponible después de asegurar el mínimo obligatorio.
- **Acciones:** primero mejorar captura, comparar modelos y acotar categorías. Solo considerar ajuste fino si hay error demostrado, datos autorizados y tiempo; requiere particiones y evaluación independientes. Entrenamiento desde cero queda fuera del mínimo. No retirar silenciosamente la IA si el piloto falla: revisar alcance con usuario/docente.
- **Salida:** comparación reproducible con el modelo base y decisión documentada de adoptar, descartar o diferir la mejora. Si no se activa esta subfase opcional, registrar la exclusión sin presentarla como experimento ejecutado.
- **Aceptación:** si se realiza, evaluar con datos independientes, conservar versiones y registrar calidad, errores y consumo frente a criterios acordados antes del experimento; adoptar solo si satisface esos criterios y las condiciones de licencia. Conservar el modelo base si la mejora no los cumple. Diferirla no bloquea la entrega cuando el detector base ya cumple el mínimo acordado.

## F09 — Reservas y contrato inteligente

**Estado (corte 2026-09-30):** 🟡 Parcial — F09.1 🟡, F09.2 ✅ en Hardhat local, F09.3 🟡, F09.4 🟡, F09.5 🟡, F09.6 🟡, F09.7 ⬜. Límite: sin testnet, sin fondos reales, sin UI de wallet/reserva y sin política de confirmaciones cerrada.
**Asignación:** ☐ Libre — escribir acá el responsable al tomar la fase.

### F09.1 — Dominio y máquina de estados de negocio

- **Entrada:** oferta versionada, usuarios y decisiones de depósito.
- **Acciones:** definir solicitud, espera de cadena, pendiente confirmada, aceptada, cancelada, rechazada y vencida; nombres técnicos finales por diseñar. Un único pendiente por inmueble y bloqueo mientras reservado.
- **Salida:** reglas y pruebas de dominio sin depender del visor.
- **Aceptación:** carrera entre clientes no produce dos reservas válidas; definir autoridad de bloqueo entre DB y contrato. Política de inicio del plazo de 24 horas explícita.

### F09.2 — Token de prueba y escrow local

- **Acciones:** contrato retiene depósito fijo autorizado. Cancelación pendiente/rechazo devuelven; vencimiento habilita devolución mediante transacción. Destino tras aceptación debe decidirse antes del contrato final.
- **Salida:** contratos y pruebas locales, sin dinero real.
- **Aceptación:** transferencias y permisos correctos; no doble devolución, aceptar después de expiración o retirar fondos ajenos. OpenZeppelin ayuda, no exime revisión.

### F09.3 — Oferta autorizada e integridad

- **Acciones:** vincular inmueble, cliente, red/contrato, versión y depósito autorizado; evitar que cliente invente monto u oferta. Definir firmante institucional y protección contra reutilización de autorizaciones.
- **Salida:** validación on-chain y en backend coherentes.
- **Aceptación:** no aceptar una autorización para otro cliente, otra red o versión inválida. Datos personales/modelos permanecen fuera de cadena; referencia/hash no equivale por sí solo a autenticidad.

### F09.4 — Wallet móvil y del personal

- **Acciones:** probar conexión, cuenta/red, solicitud de firma, rechazo del usuario y retorno a app. Elegir wallet/protocolo con soporte real. Asociar dirección a usuario mediante prueba de control apropiada, no solo texto introducido.
- **Salida:** cliente autoriza operación desde billetera externa; aceptación empresarial tiene identidad autorizada.
- **Aceptación:** RoomForge no guarda clave privada cliente; cambia de cuenta/red sin operar sobre sesión equivocada. Gas usa activo nativo de prueba distinto del token del depósito.

### F09.5 — Confirmación, eventos y conciliación

- **Acciones:** registrar hash como pendiente, comprobar contrato/red/eventos y política de confirmación. Procesar eventos idempotentes, detectar reversión/fallo, recuperar al reiniciar y resolver discrepancias DB/cadena.
- **Salida:** estados explicables, sin declarar reserva por solo recibir un hash.
- **Aceptación:** evento duplicado no duplica efectos; transacción fallida no muestra depósito confirmado; no liberar comercialmente antes de reglas de conciliación acordadas.

### F09.6 — Vencimientos y cierre

- **Acciones:** definir quién solicita devolución al vencer: cliente, tercero permitido o automatización autorizada. El contrato no se ejecuta solo por reloj. Registrar venta/alquiler externo y bloquear nuevas reservas hasta resolución.
- **Salida:** ciclo íntegro y procedimiento excepcional para operación aceptada que no culmina.
- **Aceptación:** vencimiento exige condición y tx válidas; no cobrar renta ni transferir título legal. Sin cancelación automática tras aceptación en MVP, pero no dejar fondos sin salida definida.

### F09.7 — Red pública de pruebas

- **Dependencia:** docente/red/RPC y reglas cerradas.
- **Acciones:** preparar cuentas exclusivas de prueba, tokens/faucet, contrato versionado y explorador. No alojar nodo completo si un acceso RPC adecuado basta; cuotas y disponibilidad se verifican.
- **Salida:** transacción verificable fuera de Hardhat, si se aprueba testnet.
- **Aceptación:** sin fondos reales ni billeteras personales; evidencia on-chain comprobable. Fallo de faucet/RPC no se disfraza con transacción local presentada como pública.

## F10 — Integración de las tres superficies

**Estado (corte 2026-09-30):** ⬜ Pendiente — no hay recorrido extremo a extremo; el panel sólo cubre acceso de personal y la app cliente sólo cuenta/sesión de cliente.
**Asignación:** ☐ Libre — escribir acá el responsable al tomar la fase.

### F10.1 — Flujo del agente y administrador

- **Acciones:** crear inmueble, capturar ambientes/fotos, recibir sugerencias, corregir escena/inventario, fijar precios, enviar a revisión y publicar.
- **Salida:** inmueble real visible con versión aprobada.
- **Aceptación:** ninguna transición requiere editar DB manualmente; rechazos vuelven al agente con información útil.

### F10.2 — Flujo del cliente

- **Acciones:** buscar, abrir detalle, recorrer libremente, ocultar muebles, seleccionar oferta, ver desglose y reservar mediante wallet.
- **Salida:** trayectoria móvil de extremo a extremo.
- **Aceptación:** selección persiste correctamente; rechazo de firma no deja reserva confirmada; fallo de red permite recuperar estado sin duplicar depósito.

### F10.3 — Compatibilidad y operaciones concurrentes

- **Acciones:** probar dos clientes y dos agencias, ediciones mientras se cotiza, sesiones caducadas y cargas incompletas. Versionar respuestas si se necesita evolución.
- **Salida:** resultados consistentes entre panel/apps/contrato.
- **Aceptación:** el precio mostrado para confirmar corresponde a la oferta autorizada; caché no mezcla agencias/cuentas; errores se pueden diagnosticar sin secretos.

## F11 — Despliegue real en AWS

**Estado (corte 2026-09-30):** ⬜ Pendiente — no se verificó despliegue en AWS; sólo existe el stack local con Floci.
**Asignación:** ☐ Libre — escribir acá el responsable al tomar la fase.

**Dos momentos:** un smoke pequeño temprano tras F02 y un despliegue integral después. No esperar la semana final para descubrir permisos o facturación.

### F11.1 — Cuenta, presupuesto y diseño

- **Acciones:** verificar crédito, fecha de vencimiento, servicios elegibles y región; estimar cómputo/almacenamiento/tráfico/logs. Comparar EC2/Compose/PostgreSQL persistente con ECS/Fargate/RDS. Evitar GPU cloud sin necesidad demostrada.
- **Salida:** topología elegida y presupuesto explícito.
- **Aceptación:** alertas configuradas; reconocer que no son techo automático. Incluir discos y recursos que siguen cobrando al apagar cómputo.

### F11.2 — Primer servicio real

- **Acciones:** desplegar imagen mínima funcional, acceso HTTPS y configuración sin secretos en imagen. Probar conectividad y procedimientos de actualización/rollback.
- **Salida:** endpoint de prueba real AWS, no emulador.
- **Aceptación:** se identifica versión desplegada y costo inicial; despliegue no expone PostgreSQL públicamente. Acceso del móvil usa endpoint alcanzable, no localhost del servidor.

### F11.3 — S3/SQS, permisos y persistencia

- **Acciones:** crear recursos reales con mínimo privilegio; separar configuración local/AWS. Persistencia de DB, backups, restauración temporal y acceso privado a fotos originales.
- **Salida:** aplicación conectada a servicios reales.
- **Aceptación:** subir/consultar archivo y ejecutar trabajo funciona en AWS; Floci previo no se toma como prueba de IAM, TLS o comportamiento cloud.

### F11.4 — Publicación integral y recuperación

- **Acciones:** desplegar API/panel/worker elegidos, ejecutar migraciones controladas, configurar logs y límites. APK distribuida por método acordado; no exigir publicación en tienda para demo salvo requisito docente.
- **Salida:** producto accesible y runbook de recuperación.
- **Aceptación:** reinicio conserva datos, rollback no destruye esquema, restauración comprobada. Una sola EC2 es punto único de fallo y no se presenta como alta disponibilidad.

## F12 — Calidad, seguridad y recuperación

**Estado (corte 2026-09-30):** 🟡 Parcial — CI de cuatro jobs en verde, suites backend y Flutter/panel, Pyright y Ruff sin diagnósticos nuevos frente a la línea base, y cadena de migraciones verificada contra PostgreSQL real. Límite: faltan pruebas integradas entre superficies, E2E de la trayectoria crítica, matriz de los siete criterios con mediciones y ensayo de fallos.
**Asignación:** ☐ Libre — escribir acá el responsable al tomar la fase.

La calidad se trabaja desde cada fase. Esta fase concentra mediciones, integra evidencia y decide si la entrega es aceptable, no añade toda la seguridad al final.

### F12.1 — Matriz de los siete criterios

| Criterio del docente | Qué se comprueba | Fases principales | Evidencia propuesta |
|---|---|---|---|
| Correcto | Publicación, precio, periodicidad mensual, permisos y reserva cumplen reglas | F03–F10 | Casos unitarios/integrados y recorrido de aceptación |
| Eficiente | Uso razonable de memoria, tiempos y fluidez en dispositivos objetivo | F06–F08, F11 | Mediciones reproducibles con tamaño de escena/carga declarados |
| Fiable | Reinicio, pérdida de red, duplicados y fallos no corrompen resultados | F01, F07–F11 | Inyección controlada de fallos, recuperación y restauración |
| Fácil de usar | Usuarios completan tareas sin asistencia excesiva | F02, F06, F10 | Pruebas de tareas, errores y observaciones de usuarios |
| Fácil de mantener | Módulos claros, versiones, migraciones y pruebas permiten cambios | Todas | Reproducción del entorno y cambio pequeño verificado |
| Seguridad e integridad | Datos privados aislados, precios autorizados, firma/fondos protegidos | F03–F05, F09, F11 | Pruebas negativas, revisión de permisos/contratos y secretos |
| Portabilidad | Local/AWS reproducibles y límites Android explícitos | F01, F02, F06, F11 | Smoke por entorno y compatibilidad en plataformas realmente probadas |

No se presenta esta lista como certificación ISO. Los umbrales de FPS, respuesta, error dimensional, consumo y recuperación se acuerdan usando línea base y requisitos, antes de declarar cumplimiento; no se fijan retroactivamente para aprobar cualquier resultado.

### F12.2 — Plan de pruebas por nivel

- **Acciones:** unitarias para reglas, integración PostgreSQL/S3/SQS, UI/widget para estados, contrato local para fondos y E2E para trayectoria crítica. Usar fakes en unitarias sin confundirlos con pruebas de servicios reales.
- **Salida:** catálogo de pruebas trazable a requisitos y CP canónicos cuando corresponda.
- **Aceptación:** cada ejecución registra entorno, versión, entradas, esperado, observado y resultado real. Tests omitidos/fallidos siguen visibles.

### F12.3 — Seguridad y datos

- **Acciones:** probar aislamiento tenant, accesos a archivos, cargas maliciosas, autorización de ofertas y wallet. Limitar tamaño/frecuencia de peticiones según riesgo; secretos fuera de Git; minimizar información en logs y datos de demo.
- **Salida:** hallazgos priorizados y correcciones verificadas.
- **Aceptación:** errores críticos no se ocultan bajo una etiqueta general de calidad; no declarar contrato auditado por usar una librería.

### F12.4 — Rendimiento y experiencia

- **Acciones:** medir escena pequeña y representativa, AR con tracking degradado, detector con fotos reales y API bajo carga acordada. Observar accesibilidad y recuperación de usuario desorientado.
- **Salida:** límites soportados y mejoras justificadas.
- **Aceptación:** reporte separa hardware medido de supuestos, promedio de casos extremos y pruebas técnicas de valoración subjetiva.

### F12.5 — Ensayo de fallos

- **Acciones:** interrumpir subida, reiniciar worker, duplicar mensaje, simular RPC caído y cerrar app durante reserva, en entorno controlado. Recuperar DB en destino propio aislado.
- **Salida:** procedimientos ejecutados con tiempos observados.
- **Aceptación:** inventario/fondos no se duplican y usuario obtiene estado coherente; ningún ensayo borra datos ajenos ni usa fondos reales.

## F13 — Evidencia académica, demostración y entrega

**Estado (corte 2026-09-30):** 🟡 Parcial — `docs/avance/` registra seis historias con verificación técnica y conserva visibles los casos académicos pendientes; CP-001 y CP-002 tienen evidencia en `docs/scrum/sprint-1/evidencia/`. Límite: sin guion de demostración, sin evidencia integral y sin inventario final de recursos.
**Asignación:** ☐ Libre — escribir acá el responsable al tomar la fase.

### F13.1 — Reconciliar documentación

- **Acciones:** actualizar requisitos, backlog, HU/CP, arquitectura y Scrum en su estructura canónica. Relacionar cambios de alcance con decisiones; distinguir plan y ejecución. Diagramas solo de tipos permitidos, referencias sin imágenes embebidas según reglas del proyecto.
- **Salida:** documentación académica alineada al producto real.
- **Aceptación:** no inventar responsables, fechas, burndown, capturas o pruebas; GAPs pendientes siguen visibles. Este plan no reemplaza los capítulos del modelo Grupo #12.

### F13.2 — Preparar demostración

- **Acciones:** preparar usuarios de dos agencias y cliente, tokens de prueba, dataset autorizado y un inmueble completo. Ensayar captura del aula con S23 FE y límites reales; disponer de escena previa etiquetada como respaldo, no como captura en vivo.
- **Salida:** guion con pasos, dependencias de red y alternativas honestas.
- **Aceptación:** demostrar búsqueda, recorrido libre, selección/precio, aprobación/publicación y reserva/refund; distinguir qué se hizo en aula y qué estaba preparado.

### F13.3 — Entrega y operación

- **Acciones:** registrar versión, instrucciones desde clonación, configuración ficticia, despliegue, creación de usuarios, backups y errores conocidos. Documentar fuentes/modelos/licencias y uso de pesos preentrenados sin atribuir entrenamiento propio.
- **Salida:** otro integrante puede operar el proyecto sin depender de memoria verbal.
- **Aceptación:** enlaces válidos, pasos reproducibles, sin claves reales. Commits/publicación solo bajo autorización del dueño.

### F13.4 — Cierre de recursos y mejoras

- **Acciones:** después de presentar, acordar qué servicios AWS quedan activos; apagar/eliminar únicamente recursos autorizados, conservar backups según política. Revisar costos residuales de discos, almacenamiento, IPs y logs.
- **Salida:** inventario final de recursos y pendientes.
- **Aceptación:** no prometer costo cero por apagar una instancia ni borrar todo para ahorrar. El backlog futuro conserva mejoras sin declararlas entregadas.

## 6. Decisiones abiertas y riesgos

### 6.1 Qué bloquea cada pendiente

| Pendiente | Bloquea | No bloquea |
|---|---|---|
| Ubicación de IA offline/móvil o worker | Empaquetado e integración final de inferencia | Catálogo, inventario manual, precios |
| Modelo/licencia | Distribución y uso final de ese modelo | Contrato de sugerencias y UI con fixtures explícitos |
| AR/altura/tolerancia | Afirmaciones de precisión y captura final | Editor, escena sintética y tenancy |
| Three.js/WebView y plataforma de editor | Elección final del renderizador/editor | Contrato de escena y API |
| Destino del depósito aceptado | Lógica final del escrow | Catálogo, cotizaciones y pruebas de estados ya definidos |
| Firma de la agencia y autorización de ofertas | Seguridad del contrato operativo | Formularios y reglas comerciales aisladas |
| Excepción tras aceptación | Recuperación/reapertura de esa reserva | Flujo pendiente de cancelación/rechazo |
| Testnet admitida y RPC | Demo pública de blockchain | Hardhat y tests locales |
| Moneda y redondeo | Oferta comercial definitiva | Estructura tipada sin valores comerciales inventados |
| AWS créditos/topología | Presupuesto y despliegue integral | Floci y desarrollo local |
| Código real tras reinicio | Estimación de reutilización | Documentar requisitos y construir base faltante autorizada |

### 6.2 Riesgos con respuesta explícita

- **No cabe en un mes:** revisar alcance y capacidad temprano; conservar evidencia del recorte acordado, no simular funciones para aparentar completitud.
- **AR inestable:** registrar condiciones y ofrecer corrección manual; si invalida requisito docente, renegociar, no proclamar exactitud.
- **Visor móvil lento:** reducir complejidad de escena y medir; cambiar motor solo por evidencia, no por preferencia estética.
- **IA falla en aula:** evaluar categorías reales, mantener confirmación humana y probar otro candidato; no fabricar detecciones.
- **Wallet/RPC/faucet falla:** preparar cuentas de prueba con anticipación y fallback local claramente rotulado; nunca mostrar una transacción ficticia como testnet.
- **Licencia incompatible:** cambiar candidato antes de integrarlo al producto; no asumir que uso académico elimina todas las condiciones.
- **Costos AWS:** medir y alertar, limitar horas/recursos, no contratar GPU por defecto; cualquier gasto adicional requiere decisión.
- **Datos borrados o filtrados:** respaldo/restauración, accesos mínimos y separación de entornos; no usar imágenes personales sin autorización.
- **Documentación desactualizada:** reconciliar fuentes con código y resultados; no cerrar GAPs ni reutilizar evidencia de otra versión como propia.

## 7. Criterio de producto terminado y mejoras posteriores

### 7.1 Checklist de entrega mínima

Cada casilla se comprobará al ejecutar el proyecto; se mantiene sin marcar en esta planificación.

- [ ] Las tres superficies acordadas realizan sus funciones reales.
- [ ] Dos inmobiliarias operan con aislamiento privado y catálogo público compartido.
- [ ] Venta y alquiler mensual muestran desglose correcto de muebles opcionales.
- [ ] Hay inmueble completo de un piso, escena editable y recorrido libre con límites transitables coherentes.
- [ ] Captura del dispositivo y límites de medidas están probados y documentados.
- [ ] Un modelo preentrenado aporta sugerencias reales y confirmables, con licencia y evaluación registradas.
- [ ] Ocultar muebles y excluirlos de la oferta tienen efectos distintos y comprobados.
- [ ] Billetera externa, depósito y salidas de fondos funcionan sin dinero real bajo reglas cerradas.
- [ ] Conflictos, expiración y reintentos no producen doble reserva o doble devolución.
- [ ] AWS funciona con servicios reales y presupuesto observado, no únicamente con Floci.
- [ ] Los siete criterios tienen evidencia, límites y fallos pendientes visibles.
- [ ] Documentación académica, instrucciones y guion corresponden a la versión entregada.

### 7.2 Mejoras posteriores, no dependencias ocultas

Video, mayor variedad de muebles, fine-tuning, unión automática de ambientes, múltiples pisos, exportación CAD/BIM, fotogrametría avanzada, mobiliario realista, pagos reales y suscripciones requieren nuevos requisitos, costos y validación. Se incorporan solo tras terminar el mínimo y obtener aprobación.

### 7.3 Cómo iniciar el siguiente trabajo

1. Leer este plan y la redefinición; revisar Git y estado actual sin sobrescribir otra sesión.
2. Elegir una subfase concreta y comprobar sus dependencias reales, no todo el plan.
3. Consultar pendientes que la bloquean; no volver a preguntar decisiones ya confirmadas.
4. Planificar el cambio sustancial con el flujo SDD y su autoridad correspondiente.
5. Implementar una unidad verificable, ejecutar pruebas y guardar evidencia.
6. Integrar y actualizar estado sin commits/push automáticos.

**Conclusión:** sí se puede avanzar desde infraestructura y SaaS mientras se validan las partes novedosas. El proyecto se entrega mediante fases conectadas y evidencia acumulada, no mediante una única implementación masiva ni una cadena de validaciones que detiene todo el trabajo.

## Referencias técnicas adicionales

Estas fuentes orientan selección; su mención no implica que el componente esté integrado o probado en RoomForge.

- [ARCore: dispositivos](https://developers.google.com/ar/devices) y [selección de puntos](https://developers.google.com/ar/develop/java/hit-test/developer-guide).
- [Flutter: integración nativa](https://docs.flutter.dev/platform-integration/platform-channels).
- [Torchvision: SSDLite y pesos](https://docs.pytorch.org/vision/stable/models/generated/torchvision.models.detection.ssdlite320_mobilenet_v3_large.html) y [términos de pesos](https://docs.pytorch.org/vision/stable/models.html).
- [COCO: categorías](https://docs.ultralytics.com/datasets/detect/coco/), [YOLO11](https://docs.ultralytics.com/models/yolo11/) y [licencias Ultralytics](https://www.ultralytics.com/license).
- [ONNX Runtime](https://onnxruntime.ai/docs/tutorials/mobile/).
- [SQS: entrega al menos una vez](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/standard-queues-at-least-once-delivery.html).
- [Ethereum: redes](https://ethereum.org/en/developers/docs/networks/).
- [Floci](https://github.com/floci-io/floci).
