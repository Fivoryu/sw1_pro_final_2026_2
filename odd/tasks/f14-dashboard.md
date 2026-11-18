# F14.4 — Dashboard de métricas del panel: cierre de criterios

**Objetivo:** que el dashboard de la agencia cumpla los criterios de la issue #37: métricas consistentes con la base, solo para el administrador de su agencia, con aislamiento F03.3 probado y documentación. **Plan:** `docs/plan-maestro-roomforge.md` F14.4. **Issue:** #37.
**Rama:** `feat/f14-dashboard-hardening` desde `main` (`877fdc5`).
**Ejecutores de pruebas:** backend con pytest, Ruff y Pyright; panel con `vitest` y `npm run build`.

## Estado de partida (2026-11-17, `main` en `877fdc5`)

La implementación es de otro integrante: PR #73 (`5bd1706`, `cd6adbd`) y PR #86 (`9bbcd32`). Existen `GET /api/v1/staff/agencies/{agency_id}/metrics` (`backend/app/modules/agencies/router.py`, servicio `get_agency_metrics`) y `AgencyDashboard` en el panel, visible para `agency_admin`.

Revisión contra la issue #37:

1. La ruta deja pasar al `platform_admin` sobre cualquier agencia, aunque la issue deja las métricas de plataforma fuera de alcance y pide para él el comportamiento estándar de aislamiento.
2. La ruta deja pasar a los agentes de la agencia; solo la pantalla los oculta.
3. Los inmuebles rechazados y los aprobados sin publicar no se cuentan en ninguna tarjeta, así que las métricas no cuadran con la base.
4. Las tres pruebas existentes (`tests/test_agency_metrics.py`) llaman al servicio: no prueban la ruta, el aislamiento, la sesión, las cotizaciones ni las reservas.
5. El panel no tiene pruebas del dashboard.
6. Sin contrato de API, sin registro de tarea y sin línea de estado en la sección F14.4 del plan.

## Decisiones (2026-11-17, usuario: «Si, hagamos eso»)

- **D1:** solo el `agency_admin` de la agencia de la URL. Otra agencia, los agentes y el `platform_admin` reciben `403`; sin sesión válida, `401`.
- **D2:** se agregan «Rechazados» y «Aprobados sin publicar», para que la suma de las tarjetas de inmuebles sea el total de inmuebles de la agencia.
- **D3:** el trabajo es de otro integrante; el usuario le avisa del ajuste.

## Alcance permitido

`backend/app/modules/agencies/{router,service,schemas}.py`, `backend/tests/test_agency_metrics.py`, `panel/staff-shell/src/application/agencyMetricsApi.ts`, `panel/staff-shell/src/features/agencies/AgencyDashboard.tsx` y su prueba, `docs/api/f14-dashboard.md` (nuevo), la sección F14.4, la fila de F14 del §1.4.1 y la tabla espejo del §1.4.5 del plan maestro, y este registro.

Fuera de superficie: el resto de módulos, las apps móviles y `docs/diagramas/Diagrama1.eapx`.

## Tasks

| ID | Tarea | Estado | Evidencia |
| --- | --- | --- | --- |
| T1 | Backend: autorización D1 y métricas D2, con pruebas de la ruta (aislamiento por actor, sesión, cotizaciones vigentes y vencidas, reservas por estado, suma igual al total). | ☑ | L2 |
| T2 | Panel: tarjetas D2, manejo de error y pruebas del dashboard (datos, carga, error). | ☑ | L3 |
| T3 | Cierre: contrato de API, sección F14.4 del plan y este registro. | ☑ | L4 |

## Log

- **L1 (2026-11-17):** revisión de la implementación existente y propuesta de los puntos D1 y D2; el usuario aprobó: «Si, hagamos eso».
- **L2 (2026-11-17), T1:**
  - **Pruebas nuevas:** 7 casos de la ruta en `tests/test_agency_metrics.py`, sobre las fixtures compartidas con autenticación real (`chat_support`): conteos contra la base con cotizaciones vigentes y vencidas, reservas por estado y de otra agencia, y suma igual al total; agente, otra agencia y `platform_admin` reciben `403`; agencia inexistente igual a otra agencia; sin sesión, token inválido o de cliente reciben `401`. La prueba existente del servicio se actualizó: antes afirmaba que los rechazados y los aprobados sin publicar «no se muestran».
  - **RED:** 4 fallas, las previstas (campos ausentes, y agente y `platform_admin` con `200`). Otra agencia, inexistente y sin sesión ya pasaban, y las cotizaciones y reservas ya se contaban bien.
  - **GREEN:** la ruta usa `_require_same_tenant_agency_admin`, ya existente en el mismo módulo; el servicio agrega `approved_unpublished`, `rejected` y `total`.
  - **Verificación:** suite backend 1114 aprobadas, 16 omitidas; Ruff y Pyright sin errores. Se corrió en un `.venv` local con Python 3.13, ignorado por Git, porque Docker no estaba disponible.
- **L3 (2026-11-17), T2:**
  - **Hallazgo de entorno:** con Node 26 local, 29 pruebas existentes del panel fallaban antes de cualquier cambio (`Cannot read properties of undefined (reading 'clear')`). Node 25+ define su propio `localStorage` global y pisa el del entorno de pruebas. Con `NODE_OPTIONS=--no-experimental-webstorage` pasan las 282; el CI usa Node 22 y no lo sufre. No es un defecto de `main`.
  - **Pruebas nuevas:** 6, en `agencyMetricsApi.test.ts` y `AgencyDashboard.test.tsx`. RED: 4 fallas; pasaban la llamada a la API y el estado de carga.
  - **GREEN:**
    - el cliente lanza `AgencyMetricsError` con el estado HTTP;
    - el dashboard muestra «Aprobados sin publicar», «Rechazados» y «Total de inmuebles», con secciones accesibles por nombre;
    - un `403` muestra «Solo el administrador de la agencia puede ver estas métricas.» sin números, y otro error ofrece «Reintentar»;
    - se descarta una respuesta que llega después de desmontar la pantalla.

    Se conservó el diseño de tarjetas existente.
  - **Verificación:** `vitest` 288/288 y `npm run build` sin errores.
- **L4 (2026-11-17), T3:**
  - contrato en `docs/api/f14-dashboard.md`;
  - estado en la sección F14.4 del plan;
  - la fila de F14 del §1.4.1 pasa de «Sin implementación integrada» a 🟡 Parcial, con el detalle por subfase;
  - se corrigieron las etiquetas corridas de la tabla espejo del §1.4.5 (#36 es captura guiada, #37 dashboard, #39 tour), verificadas contra los títulos de GitHub.

  Pendiente fuera de esta tarea: sin prueba contra PostgreSQL real.
- **L5 (2026-11-17), prueba manual en el stack local:**
  - **Stack:** levantado con el código de esta rama; base local migrada de `0018_listing_photos` a `0034_listing_reviews`; los cinco servicios `healthy`; la ruta de métricas sin sesión respondió `401`.
  - **Recorrido del usuario como `agencia@example.test`:** la agencia de prueba tenía 10 inmuebles (3 publicados y 7 aprobados sin publicar). Al retirar uno del catálogo desde la bandeja y recargar, «Publicados» y «Aprobados sin publicar» cambiaron de grupo y el total siguió en 10. Resultado informado por el usuario: «Si, funciona exactamente asi».
  - **Límite:** la respuesta `403` para el agente y el `platform_admin` solo está cubierta por pruebas automáticas, porque el panel no les muestra el dashboard.

