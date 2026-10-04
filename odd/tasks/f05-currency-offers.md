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
- [x] **F05M-T2 — Tasas administradas (backend).** Tabla de tasas (base USD) con vigencia y autoría; rutas de plataforma para crear/listar tasas; lectura pública de la tasa vigente; matriz de conversión por cruce (`BOB→USD→X`); pruebas de autorización (`platform_admin` escribe, otros `403`).
- [x] **F05M-T3 — Cotización en moneda elegida (backend).** `POST /quotes` (y equivalente vigente) acepta `target_currency`; total convertido con la tasa vigente y congelado en la instantánea con su tasa; validación de que la reserva usa la moneda de la instantánea; contrato documentado.
- [x] **F05M-T4 — F05.1 mobiliario completo (backend).** Categoría, habitación, dimensiones/origen y vínculo visual en `ListingExtra`; gestión de referencias al eliminar/reemplazar; contrato documentado.
- [x] **F05M-T5 — Panel (moneda + tasas).** Selector de moneda en autoría de inmueble; pantalla de administración de tasas para `platform_admin`; desglose convertido en la bandeja/visión de cotizaciones.

## Registro de ejecución (continuación)

### F05M-T5 — Panel: tasas y moneda (2026-10-04)

- **Alcance ajustado a la realidad del panel:** no existe pantalla de autoría de inmuebles (el agente crea en la app de captura, T7) ni vista de cotizaciones; el selector de moneda de autoría y el desglose de cotizaciones no aplican acá. La unidad entregó la administración de tasas y la visibilidad de moneda.
- Nuevo `application/exchangeRatesApi.ts` (patrón `staffListingsApi`): `getCurrentExchangeRates`, `getExchangeRateHistory`, `createExchangeRate`, error tipado con estado; suite propia (éxitos, 401/403/422/503, fallo de transporte).
- Nueva pantalla `features/rates/ExchangeRatesAdmin.tsx`, visible solo para `platform_admin` (gating por rol en `ProtectedStaffShell`, reemplazando el placeholder): tasas vigentes (BOB/USDT administradas, USD fijo `1.00000000` etiquetado como referencia), historial (más nuevo primero) y formulario de alta (moneda BOB/USDT, unidades por USD con validación cliente de >0 y ≤8 decimales; el servidor queda como autoridad). Mensajes de error en español profesional.
- `StaffListing` conserva el campo `currency` que el backend ya envía; la bandeja muestra la moneda junto a los montos (lista y detalle, campo «Moneda»). Aserciones legacy COP→BOB actualizadas según la decisión F05.
- TDD: RED observado (imports inexistentes, heading ausente, moneda perdida por el DTO) → GREEN; panel 116/116 en 10 archivos (+15), build limpio sin dependencias nuevas.
- Commit de work unit (ver git log) — sin push.
- [x] **F05M-T6 — App cliente (moneda elegida).** Selector de moneda de visualización persistente; precio convertido junto al original; cotización en la moneda elegida con aviso de tasa congelada.

## Registro de ejecución (continuación)

### F05M-T6 — App cliente (2026-10-04)

- `DisplayCurrency` en `CatalogController` (BOB default, setter notificante e idempotente); selector en el catálogo («Moneda de visualización»); formateador `formatMoney(amount, currency)` etiqueta con el código de la moneda del servidor; detalle muestra «Cotizable en X» solo si difiere de la elegida. **Sin conversión del lado cliente** — el servidor es la única autoridad.
- Etiquetas de filtros de precio dejaron el «(COP)» hardcodeado (falso desde T1); la prueba de `catalog_api_test` conserva su JSON con «COP» inline como prueba de paso de cadenas de moneda.
- **Ítem de cotización omitido honestamente:** la app cliente NO tiene flujo de solicitud de cotización aún (pestaña prototype); cuando exista, debe enviar `target_currency` y renderizar `display_totals`/`display_rate` con «Tasa congelada al cotizar». Queda registrado como pendiente para la unidad de cotizador.
- **Persistencia pendiente:** no hay dependencia de preferences en pubspec (prohibida en superficie); la moneda vive en estado del controller y se resetea al reiniciar. Unidad futura puede persistirla.
- TDD: RED observado (3 archivos no cargaban: símbolos inexistentes) → GREEN 83/83 (+7), `flutter analyze` sin hallazgos; verificación independiente del orquestador vía cmd.exe (flutter nativo WSL falla por CRLF).
- Commit de work unit (ver git log), sin push.
- [x] **F05M-T7 — App de captura (moneda).** Selección de moneda al crear/editar inmueble; validaciones equivalentes a la API.

## Registro de ejecución (continuación)

### F05M-T7 — App de captura (2026-10-04)

- `ListingCurrency` enum (BOB/USD/USDT, parseo fail-closed); `StaffListing.currency` requerido; selector «Moneda» en el editor habilitado solo al crear y de solo-lectura al editar (echo de la moneda almacenada); precios etiquetados con su moneda en «Mis inmuebles» y en el editor.
- **Hallazgo del escritor:** el PUT del backend sobrescribía la moneda (default `BOB` al omitirla) — un cliente que no la enviara reseteaba un inmueble USD/USDT a BOB silenciosamente. Corregido en backend en la misma ronda: la edición ignora `currency` (inmutable tras la creación), con RED→GREEN (`test_edit_keeps_the_stored_currency_regardless_of_the_payload`) y contrato actualizado (`docs/api/f04-publications-v1.md`, con nota histórica). La app edita solo-lectura coherente con esa inmutabilidad.
- Extras: el editor no gestiona mobiliario hoy; no se añadió autoría de extras (solo se cablea lo existente).
- TDD: RED observado (3 archivos no compilaban: símbolos inexistentes) → captura 86/86 (+10), `flutter analyze` y `dart format` limpios; backend 579/3 tras el fix, Ruff limpio. Verificación flutter del orquestador vía cmd.exe.
- Commits (ver git log), sin push.
- [x] **F05M-T8 — Escrow con USDT.** Mock USDT (6 decimales) y despliegue parametrizado del escrow; pruebas Hardhat del flujo de reserva con USDT y con el token de prueba existente.

## Registro de ejecución (continuación)

### F05M-T8 — Escrow con USDT (2026-10-04)

- **Decisión de diseño:** el escrow solo mueve unidades crudas del token; la escala por moneda vive en el backend (`TOKEN_UNIT_SCALES`: BOB/USD ×100, USDT ×10⁶). El constructor pasó de exigir exactamente 2 decimales a aceptar **decimales ≥ 2** (rechaza < 2, el piso comercial), con NatSpec neutral: los importes van en las unidades del token y escalar es responsabilidad del que llama. La regla histórica «denominado en COP» quedó removida del contrato y del README.
- Nuevo `contracts/contracts/MockUSDT.sol`: ERC20 de 6 decimales (estilo espejo de `RoomForgeTestToken`, mint con owner).
- Pruebas: flujo completo de reserva (depósito → aceptar, rechazo con reembolso, cancelación con reembolso, expiración permisionless) con el mock de 6 decimales y montos escalados (1.00 USDT = 1.000.000 unidades), más rechazo de token de 1 decimal; los 34 tests previos con el token de 2 decimales siguen en verde.
- TDD: RED observado (6 fallos por artefacto `MockUSDT` inexistente) → GREEN 40/40; `hardhat compile` limpio. El escritor instaló `node_modules` con `npm ci --ignore-scripts` (lockfile pinned) para poder verificar; sin cambios en package.json/lockfile.
- Commit de work unit (ver git log), sin push.
- [x] **F05M-T9 — Verificación integrada.** Suites completas de las cuatro superficies; PostgreSQL descartable con la migración de moneda; recorrido manual: publicar en BOB, cotizar en USD y en USDT, reservar contra el escrow; actualización del plan maestro al integrar.

## Registro de ejecución (continuación)

### F05M-T9 — Verificación integrada (2026-10-04)

- Batería completa en verde (ejecutada por `gentle-ai-verify`): backend 579/3 + Ruff + Pyright; panel 116/116 + build; cliente 83/83 + analyze; captura 86/86 + format + analyze; Hardhat 40/40.
- **PostgreSQL 16 real (desechable):** cadena completa `alembic upgrade head` hasta `0016_listing_extra_details (head)` — migraciones 0013–0016 verificadas en PostgreSQL; pruebas con guardas en verde (`test_f04_publications_postgres` con `ROOMFORGE_POSTGRES_DATABASE_URL`, `test_staff_identity_postgres` con su guarda `ROOMFORGE_R6_DATABASE_URL`). Contenedor y volumen descartados al terminar.
- **Defecto encontrado y corregido:** T4 había dejado un diagnóstico Pyright nuevo (`test_catalog.py:953`, `dbapi_connection` posiblemente sin asignar en el `finally`) que su registro no detectó; corregido con commit propio (`test(catalog): bind the guard connection before the try block`) y Pyright de vuelta al baseline exacto (18 preexistentes, 0 nuevos).
- Plan maestro: párrafo de avance en rama agregado a la sección F05 (con la decisión de moneda que sustituye a la de F00); las filas de §1.4.1 se actualizan al integrar en `main`, según convención del documento.
- **Pendiente del usuario (recorrido manual):** publicar en BOB desde el panel/captura, cotizar en USD y USDT desde la app cliente, y reservar contra el escrow con USDT en el stack local. La batería automatizada no lo cubre.
- Nota de infraestructura para futuras corridas: la guarda de PostgreSQL varía entre archivos (`ROOMFORGE_POSTGRES_DATABASE_URL` vs `ROOMFORGE_R6_DATABASE_URL`).

## Registro de ejecución

### F05M-T1 — Núcleo de moneda (2026-10-03)

- Nuevo `backend/app/core/money.py`: `SupportedCurrency` (`BOB`/`USD`/`USDT`), `validate_currency` que falla cerrado y `format_money_amount` con 2 decimales y `ROUND_HALF_UP`. Implementado por subagente escritor (`gentle-ai-worker`) con TDD: RED observado (módulo inexistente, autoría rechazando USD/USDT, revisión 0013 inexistente) y luego GREEN.
- `Listing` y `QuoteSnapshot` ganan columna `currency` (default `BOB`, CHECK de enum); migración `0013_listing_currency` añade ambas columnas y renombra `deposit_amount_cop` → `deposit_amount` con sus CHECK; el downgrade rechaza monedas no `BOB` en vez de convertir implícitamente. La moneda del inmueble se propaga a catálogo, cotizaciones y reservas sin conversión (T2/T3).
- `cop_to_token_units` → `money_to_token_units` (escala ×100 sin cambios, mensajes neutrales); cero referencias a COP en `backend/app`.
- Verificación independiente del orquestador: suite backend 531 aprobadas / 3 omitidas, Ruff limpio; Pyright conserva 19 diagnósticos preexistentes (`eth_account`/`eth_utils`, archivos no tocados). Migración verificada solo con SQLite; PostgreSQL descartable queda para F05M-T9.
- Commit de work unit `b99ce22` (`feat(backend): replace COP with typed BOB/USD/USDT currency support`), sin push.
- **Revisión nativa (RDD):** lineage `review-e3dd0a3ee264fc17`, riesgo medium (cambio ejecutable en la migración). El lente `review-reliability` (validado por refuter) halló un CRITICAL real: `money_to_token_units` seguía multiplicando ×100 para USDT, que el escrow de 6 decimales (T8) recibiría con fondos insuficientes (`R3-UsdtTokenScale`). Corrección acotada aplicada y validada: `TOKEN_UNIT_SCALES` por moneda en `app/core/money.py` (BOB/USD → ×100, USDT → ×10⁶), `money_to_token_units(amount, *, token_scale)` y helper `_deposit_token_units` en reservas; commit `386b7e2` (`fix(reservations): scale deposits to token units per currency`). Suite 531 aprobadas / 3 omitidas, Ruff limpio tras la corrección. Revisión cerrada en `approved` con autoridad quemada.
- Lección registrada: la corrección debía commitearse para que el proveedor reconociera el candidato corregido (`corrected_candidate_unavailable` con el fix sin commit).

(aún sin más entradas)

### F05M-T4 — F05.1 mobiliario completo (2026-10-04)

- **Decisión de contrato (del orquestador, a pedido del escritor):** la API F04 no autorizaba extras (regla histórica «La API F04 no modifica extras»); F05.1 exige lista editable y el mapa UX asigna la autoría a la app de captura (T7), así que la autoría de extras entró a la API de autoría de inmuebles como extensión F05.1, con la regla histórica marcada como reemplazada (2026-10-04) en el contrato.
- `ListingExtra` gana 8 columnas opcionales: `category`, `room`, `origin`, `visual_reference` (texto libre con límites y CHECK no-vacío), `width_cm`/`height_cm`/`depth_cm` (enteros ≥ 1) y `quantity` NOT NULL default 1. Migración `0016_listing_extra_details` (batch SQLite, recreación de triggers; PostgreSQL queda para T9).
- **Autoría por diff de ID estable:** POST inserta con IDs nuevos; PUT concilia por `extra_id` (actualiza en sitio / inserta / elimina); `extras` omitido no toca nada, `[]` explícito elimina todos; conjunto idéntico → `offer_version` sin cambio; cambio de `quantity` es cambio de oferta (trigger 0007 extendido) y cambio solo descriptivo no la bumpa. `extra_id` desconocido → `422` sin mutación.
- Totales de oferta: `Σ(precio × cantidad)`; con default 1 el aritmética legacy queda idéntica. Las líneas de cotización no cambian de forma (el monto ya incluye cantidad) — parsers de clientes intactos.
- Cantidades explícitas: nada las deriva sumando detecciones de fotos repetidas (F08 no existe aún; `origin` documenta procedencia, nada automatiza).
- Snapshot inmutable verificado por UPDATE/DELETE crudos sobre la copia.
- TDD: RED observado (16 pruebas: `422 validation_error` por campo rechazado) → GREEN; suite 578 aprobadas / 3 omitidas (+24), Ruff limpio, Pyright sin diagnósticos nuevos.
- Commit de work unit `e4101b5` (`feat(catalog): complete furniture inventory with stable-ID extras authoring`), sin push.

### F05M-T3 — Cotización multi-moneda (2026-10-04)

- `POST /api/v1/quotes` acepta `target_currency` opcional (BOB/USD/USDT). Si falta o coincide con la moneda del inmueble, la cotización se comporta como antes. Si difiere: conversión origen → USD → destino en `Decimal` exacto (cuantizada a 2 decimales con `ROUND_HALF_UP` solo al final), usando las tasas vigentes administradas.
- La instantánea congela la conversión: nuevas columnas `display_currency`, `display_one_time_total`, `display_monthly_total`, `base_units_per_usd`, `display_units_per_usd` con CHECK todo-o-nada; la fila es inmutable — un cambio de tasa posterior no altera una cotización existente (probado) y las nuevas usan la tasa nueva.
- Respuesta: bloque `display_totals` + `display_rate` solo cuando hay conversión (omitido con `exclude_unset`, que preserva los `extra_id: null` explícitos de las líneas — defecto detectado y corregido en refactor). Tasa faltante → falla cerrada `503 exchange_rate_unavailable`; nunca se inventa una tasa.
- Reservas y depósitos fuera de alcance: el depósito sigue en la moneda del inmueble (escala por `TOKEN_UNIT_SCALES` ya cubierta en T1).
- Migración `0015_quote_display_currency` (patrón batch SQLite; PostgreSQL queda para T9).
- TDD: RED observado (5 fallos: campo rechazado, migración ausente) → GREEN 6/6 → 84/84 enfocadas; suite completa 561 aprobadas / 3 omitidas, Ruff limpio, Pyright sin diagnósticos nuevos en módulos tocados.
- Commit de work unit `5f059f2` (`feat(catalog): quote conversion with frozen display rates`), sin push.

### F05M-T2 — Tasas administradas (2026-10-04)

- Nuevo módulo `backend/app/modules/exchange_rates/`: tabla `exchange_rate` con `currency` (BOB/USDT; USD fijo en 1.0 y nunca almacenado), `units_per_usd Numeric(18,8) > 0`, `created_by String(36)` FK a `staff_account.id` (corrección del orquestador: la especificación inicial pedía entero y la PK de staff es UUID — el escritor detectó la incompatibilidad y frenó antes de escribir). Migración `0014_exchange_rates` con patrón batch compatible con SQLite.
- Rutas: `POST /api/v1/platform/exchange-rates` (solo `platform_admin`, 201/401/403), `GET /api/v1/platform/exchange-rates` (historial, más nuevo primero) y `GET /api/v1/exchange-rates/current` (público, incluye USD fijo `1.00000000`). Tasas vigentes = última fila; el historial queda para auditoría; sin pos-fechado en esta unidad.
- Conversión exacta en `Decimal` (nunca flotante): origen → USD → destino, cuantizada a 2 decimales con `ROUND_HALF_UP` solo al final; identidad misma moneda; falla cerrada si falta la tasa de una moneda.
- El escritor registró el router en `app/main.py` (superficie autorizada en la delegación) y documentó los tres endpoints en `docs/api/f02-api-contract.md`.
- TDD: RED observado (`ModuleNotFoundError` del módulo nuevo) y luego GREEN 23/23 enfocadas; suite completa 554 aprobadas / 3 omitidas, Ruff limpio, Pyright sin diagnósticos nuevos.
- Commit de work unit `3714b67` (`feat(exchange-rates): administer BOB/USDT rates against USD with public read`), sin push.
- **Revisión nativa:** el facade devolvió payloads corruptos durante el acknowledge (salida no confiable, incluidas dos llamadas malformadas del orquestador que se retiraron). Se resolvió por inspección nativa autoritativa (`gentle-ai review status` del usuario): una única entrada `approved` (lineage `review-9ca7465c2a9c4f58`), `problems: []`, lock liberado, sin hallazgos ni trabajo capturado pendiente. El leve hallazgo informativo `R3-001` (WARNING, `test_currency_migration.py:31`) queda como trabajo posterior; no bloquea. La discrepancia de lineage entre facade y almacén nativo se resuelve a favor del inventario nativo autoritativo.
- Del review de T1 quedó un hallazgo informativo no bloqueante (`R3-001`, WARNING, `reservations/service.py:99`): trabajo posterior, se atiende en una unidad propia.

### F05M-T10 — Ingesta automática de tasas oficiales (2026-10-04)

- **Decisión del usuario:** descartada la variante «sugerir tasa» (implementada y descartada sin commitear; preservada en `git stash` como `T10-suggest-descartado-2026-10-04`); la fuente externa debe ser el cambio oficial y llegar automáticamente.
- **Fuentes integradas:** USDT desde el spot público de Coinbase (midpoint de exchange — documentado honestamente como no oficial) con etiqueta `coinbase`; BOB como tasa oficial administrativamente fija del BCB leída de `ROOMFORGE_OFFICIAL_BOB_RATE` (default `6.96`) con etiqueta `bcb-static`. USD nunca se ingiere (referencia fija 1.0). Todo falla cerrado: timeout, no-200, JSON malformado, valor no positivo → `RateSourceError`, nunca se inventa una tasa.
- **Refresco automático:** tarea de fondo en el lifespan de FastAPI, cada `ROOMFORGE_RATE_REFRESH_SECONDS` (default 21600 = 6h; ≤0 deshabilita; primera corrida solo tras el primer intervalo, así la suite nunca toca la red); sobrevive excepciones y se cancela al apagar. Crea una fila nueva por moneda solo cuando el valor traído difiere del último almacenado (las filas manuales se sustituyen, nunca se sobrescriben); resultado por moneda `created|unchanged|error`.
- Migración `0017_exchange_rate_source`: columna `source` en `exchange_rate` (default `manual`); desviación aprobada por el orquestador: `created_by` pasa a nullable porque las filas del sistema no tienen autor staff. Panel muestra la etiqueta de fuente («BCB oficial»/«Coinbase»/«Manual») en vigentes e historial.
- TDD: RED observado (módulo inexistente; etiquetas ausentes) → backend 607/3 (+28), panel 118/118 (+2), Ruff limpio, Pyright en baseline (18). PostgreSQL real de 0017 queda para la próxima corrida T9-style.
- Commit de work unit (ver git log), sin push.
