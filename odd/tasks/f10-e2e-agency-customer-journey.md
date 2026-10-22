# F10 — E2E automatizado del recorrido agencia → cliente

Header: un E2E de extremo a extremo que recorre el camino real entre superficies — alta del inmueble
por la agencia, revisión y publicación desde el panel, catálogo/detalle/cotización del cliente y
reserva según lo integrado de F09 — contra PostgreSQL real con la cadena completa de migraciones.

## Specs

- S1: Issue #29 verbatim — "Automatizar la verificación del recorrido entre superficies, hoy cubierto
  solo por recorridos manuales registrados."
- S2: Alcance verbatim de la issue — "E2E automatizado del recorrido real integrado: alta de inmueble
  (captura o API) → revisión en panel → publicación → catálogo y detalle del cliente → cotización →
  (reserva según lo integrado de F09 al momento de ejecutar)."
- S3: "Aislamiento verificado dentro del E2E (otra agencia no ve el inmueble)."
- S4: "❌ Incluir funciones no integradas para 'completar' el recorrido; capturas ficticias."
- S5: Criterios — "El E2E corre verde desde el repositorio limpio (o su exclusión de CI está
  documentada con motivo)" y "Detecta al menos un camino de regresión real entre superficies".
- S6: Regla del espejo (plan §1.4.5) — rama `feat/f10-…` → PR con `Closes #29` → merge → actualizar
  fila §1.4.1 y tabla espejo del plan maestro.

## Decisiones

1. **Nivel del E2E (tarea 1 de la issue):** API-to-API sobre PostgreSQL real con la cadena Alembic
   completa y `TestClient`, el mismo nivel del E2E de F04 (`test_f04_publications_postgres.py`).
   Los actores de staff se inyectan por override de `get_active_staff`.
   Límites documentados: el login real con TOTP del panel lo cubre el E2E propio del panel
   (`panel/staff-shell/e2e/staff-login.e2e.test.mjs`); las superficies Flutter verifican su contrato
   con tests de integración sobre backends falsos (registros F04C/F04K). El E2E no abre navegadores
   ni emuladores.
2. **Semillas reproducibles:** las agencias se insertan como filas (mismo patrón F04); todo lo demás
   del recorrido se construye por la API (alta, edición, transiciones, cotización, reserva), nunca
   con SQL directo sobre estado de negocio.
3. **Base de datos:** propia y virgen `roomforge_f10_*` vía `ROOMFORGE_F10_DATABASE_URL`; el test se
   salta si la variable no existe (mismo patrón que F04/R6). El CI crea la base y exporta la variable.
4. **Reserva:** incluida según lo integrado de F09 hoy (backend con escrow local); lo que no esté
   integrado de F09.5–F09.6 queda como límite documentado, no se simula (S4).

## Tasks

- T1 (S1, S2): E2E `backend/tests/test_f10_agency_customer_journey.py` con fixture de base virgen,
  semillas de agencias y recorrido completo por la API con aserciones de aislamiento (S3).
- T2 (S5): demostración de detección de regresión: mutación temporal en código de app (working tree,
  sin commit) → el E2E falla → revertir; registrar el resultado en este documento.
- T3 (S1): CI — tercera base `roomforge_f10_runner` y export de `ROOMFORGE_F10_DATABASE_URL`.
- T4 (S5, S6): verificación completa (suite local, ruff, pyright, CI verde) y PR con `Closes #29`;
  tras el merge, actualizar fila §1.4.1 y tabla espejo del plan maestro.

## Log

- L1 (2026-10-16): "Ya hice el merge, podemos hacer el f10?" — pedido verbatim; el humano mergeó
  #43/#44 y pide F10 (issue #29).
- L2 (2026-10-16): Exploración — E2E existentes: panel (Node) y F04 contra PostgreSQL desechable;
  contratos confirmados: transiciones staff (submit/approve/publish admin-only), cotización
  POST /api/v1/quotes, reservas con cliente autenticado y escrow local.
- L3 (2026-10-16): E2E verde en CI (run 38957156775, run 7 del PR #45): Backend "749 passed" con el
  journey incluido. Ajustes de contrato destapados por cada run: offer_version 2 al crear con extras,
  estado "pending" tras submit, listado staff paginado (StaffListingPage.listings), cambio de actor
  antes del challenge de wallet, 201 en el link de ambas wallets, y aritmética de versiones del
  trigger (aserción semántica: reprecio > versión cotizada; snapshot inmutable).
- L4 (2026-10-16): Demostración de detección de regresión (T2, criterio S5) en rama desechable
  feat/f10-e2e-mutation-demo (eliminada tras la evidencia, nunca mergeada): mutación deliberada que
  quita los filtros approval_status e is_published del catálogo público. Primera demo (run
  38959304145): la suite unitaria de catálogo cazó la mutación. Segunda demo con solo el journey
  (run 38962750335): el propio E2E falló con "AssertionError: a draft listing must never reach the
  customer catalog" — detección de regresión entre superficies a nivel recorrido, confirmada.
  La rama feat/f10-e2e-agency-customer-journey nunca llevó la mutación (filtros intactos verificados).
