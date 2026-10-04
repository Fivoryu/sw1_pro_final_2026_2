# F05 — Mobiliario, precios y ofertas versionadas + multi-moneda (BOB/USD/USDT)

## Objetivo

Completar la Fase 5 del `docs/plan-maestro-roomforge.md` (F05.1 mobiliario completo es el hueco; F05.2–F05.4 ya están integrados) y añadir, por decisión del usuario del 2026-10-03, soporte multi-moneda con **precio dual/multiple obligatorio**: el cliente ve y cotiza en la moneda que elija entre **BOB, USD y USDT**, con conversión automática. El COP **se reemplaza** y **USDT también entra al escrow** de F09.

## Decisiones tomadas (2026-10-03, confirmadas por el usuario)

1. **Multi-moneda dual/multiple obligatoria**: todo precio se expresa en la moneda del inmueble y puede mostrarse/cotizarse convertida a la moneda elegida por el cliente. La conversión es server-side y nunca confía en el cliente.
2. **COP eliminado**: las monedas soportadas pasan a ser exactamente `BOB`, `USD` y `USDT` (enum tipado, 2 decimales comerciales con `Decimal` y `ROUND_HALF_UP`, igual que la regla vigente). Los datos de desarrollo existentes en COP se ajustan por migración.
3. **Tasas administradas**: sin API externa. El `platform_admin` carga tasas de cambio (referencia USD) con vigencia; la lectura de la tasa vigente es pública. La cotización congela la tasa usada en su instantánea (F05.4): si la tasa cambia, las cotizaciones existentes no se reescriben y las nuevas salen con la tasa vigente.
4. **USDT en el escrow**: los contratos de `contracts/` admiten un token tipo USDT (mock con 6 decimales para Hardhat) como activo de reserva, además del token de prueba existente.
5. **Flujo**: ODD con registros por unidad; sin artefactos SDD.

## Trazabilidad

- Plan maestro: F05.1–F05.4 (§F05) y la regla «dinero comercial y token de prueba no tienen conversión económica implícita», que esta unidad **reemplaza por decisión explícita del usuario**: ahora la conversión entre BOB/USD/USDT es una función de producto con tasas administradas; el token de prueba de Hardhat sigue sin conversión económica.
- Nota: esta unidad actualiza la fila F00 del plan (moneda confirmada pasa de COP a BOB/USD/USDT) cuando se integre.

## Alcance permitido (por unidad)

- T1–T3: `backend/app/modules/catalog/`, `backend/app/modules/quotes/` (o módulo donde vivan las cotizaciones), `backend/app/modules/reservations/` (solo lectura de moneda/tasa de la instantánea), `backend/alembic/versions/`, `backend/app/core/` (dinero/moneda), `backend/tests/`, `docs/api/f04-publications-v1.md`, `docs/api/f02-api-contract.md`.
- T4: `backend/app/modules/catalog/` (mobiliario), migraciones, tests, contrato.
- T5: `panel/staff-shell/src/` (autoría de inmuebles con moneda, administración de tasas, desglose).
- T6: `apps/cliente_mobile/lib/` (selector de moneda, precio convertido, cotización).
- T7: `apps/captura_mobile/lib/` (moneda al crear/editar inmueble).
- T8: `contracts/` (mock USDT, escrow parametrizado, pruebas Hardhat).
- T9: verificación integrada y actualización de `docs/plan-maestro-roomforge.md` (F00, F05, F09) al integrar.

Fuera de superficie: `docs/diagramas/Diagrama1.eapx`, `openspec/`, identidad de personal, infraestructura Compose salvo variables nuevas necesarias.

## Restricciones

- TDD estricto (RED → GREEN → REFACTOR) en cada unidad de backend/panel/apps: pytest, `ruff check app tests`, `pyright app tests`, `npm test` + build, `flutter test` + `flutter analyze`, Hardhat `npx hardhat test`.
- El servidor recalcula siempre: el cliente nunca envía totales ni tasas.
- Ninguna tasa ni total en flotante binario: `Decimal` en backend, unidades mínimas en contratos.
- Cambios de contrato de API documentados antes de tocar clientes (T5–T7 consumen lo documentado en T1–T3).
- Sin commit ni push sin autorización explícita del usuario (para cada unidad, igual que F04).

## Tareas

- [x] **F05M-T1 — Núcleo de moneda (backend).** Enum tipado `Currency` (`BOB`, `USD`, `USDT`), reemplazo del `Literal["COP"]` en catálogo y del campo moneda en cotizaciones/reservas; validación de formato `.2f` por moneda; migración Alembic que reescribe datos `COP` a `BOB` (datos de desarrollo, decidir y registrar el mapeo) o los invalida; regresión completa de suites.
- [ ] **F05M-T2 — Tasas administradas (backend).** Tabla de tasas (base USD) con vigencia y autoría; rutas de plataforma para crear/listar tasas; lectura pública de la tasa vigente; matriz de conversión por cruce (`BOB→USD→X`); pruebas de autorización (`platform_admin` escribe, otros `403`).
- [ ] **F05M-T3 — Cotización en moneda elegida (backend).** `POST /quotes` (y equivalente vigente) acepta `target_currency`; total convertido con la tasa vigente y congelado en la instantánea con su tasa; validación de que la reserva usa la moneda de la instantánea; contrato documentado.
- [ ] **F05M-T4 — F05.1 mobiliario completo (backend).** Categoría, habitación, dimensiones/origen y vínculo visual en `ListingExtra`; gestión de referencias al eliminar/reemplazar; contrato documentado.
- [ ] **F05M-T5 — Panel (moneda + tasas).** Selector de moneda en autoría de inmueble; pantalla de administración de tasas para `platform_admin`; desglose convertido en la bandeja/visión de cotizaciones.
- [ ] **F05M-T6 — App cliente (moneda elegida).** Selector de moneda de visualización persistente; precio convertido junto al original; cotización en la moneda elegida con aviso de tasa congelada.
- [ ] **F05M-T7 — App de captura (moneda).** Selección de moneda al crear/editar inmueble; validaciones equivalentes a la API.
- [ ] **F05M-T8 — Escrow con USDT.** Mock USDT (6 decimales) y despliegue parametrizado del escrow; pruebas Hardhat del flujo de reserva con USDT y con el token de prueba existente.
- [ ] **F05M-T9 — Verificación integrada.** Suites completas de las cuatro superficies; PostgreSQL descartable con la migración de moneda; recorrido manual: publicar en BOB, cotizar en USD y en USDT, reservar contra el escrow; actualización del plan maestro al integrar.

## Registro de ejecución

### F05M-T1 — Núcleo de moneda (2026-10-03)

- Nuevo `backend/app/core/money.py`: `SupportedCurrency` (`BOB`/`USD`/`USDT`), `validate_currency` que falla cerrado y `format_money_amount` con 2 decimales y `ROUND_HALF_UP`. Implementado por subagente escritor (`gentle-ai-worker`) con TDD: RED observado (módulo inexistente, autoría rechazando USD/USDT, revisión 0013 inexistente) y luego GREEN.
- `Listing` y `QuoteSnapshot` ganan columna `currency` (default `BOB`, CHECK de enum); migración `0013_listing_currency` añade ambas columnas y renombra `deposit_amount_cop` → `deposit_amount` con sus CHECK; el downgrade rechaza monedas no `BOB` en vez de convertir implícitamente. La moneda del inmueble se propaga a catálogo, cotizaciones y reservas sin conversión (T2/T3).
- `cop_to_token_units` → `money_to_token_units` (escala ×100 sin cambios, mensajes neutrales); cero referencias a COP en `backend/app`.
- Verificación independiente del orquestador: suite backend 531 aprobadas / 3 omitidas, Ruff limpio; Pyright conserva 19 diagnósticos preexistentes (`eth_account`/`eth_utils`, archivos no tocados). Migración verificada solo con SQLite; PostgreSQL descartable queda para F05M-T9.
- Commit de work unit `b99ce22` (`feat(backend): replace COP with typed BOB/USD/USDT currency support`), sin push.

(aún sin más entradas)
