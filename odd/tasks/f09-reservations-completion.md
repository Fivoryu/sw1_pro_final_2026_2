# F09 — Plan de cierre de reservas y contrato inteligente

**Estado:** 🟡 Parcial (corte 2026-10-14); el flujo local cliente→cotización→reserva está verificado, pero falta el recorrido wallet/escrow integrado y la aprobación del contrato API general.
**Fuentes canónicas:** `docs/plan-maestro-roomforge.md` (F09 y §1.4.1), `docs/redefinicion-roomforge.md` y las decisiones registradas en `odd/tasks/cliente-catalog.md`.
**Objetivo:** completar el recorrido de reserva ya respaldado por backend y escrow local, incorporar la experiencia real del cliente y registrar con claridad los límites de la cadena local.

## 1. Estado de partida contrastado

- F09.1–F09.6 tienen implementación en backend y contrato: estados, exclusión de reserva activa, snapshot comercial, permisos EIP-712, conciliación de receipts/eventos y escrow Solidity con RFT/MockUSDT local.
- CC-07 está implementada en la app cliente: cotización real del servidor, solicitud/listado de reservas y estados vacíos/carga/error. El 2026-10-14 se probó desde el teléfono una cotización BOB de `250000.00` y se creó una reserva `pending` con depósito `10.00 BOB`; `deposit_confirmed_at` permaneció nulo.
- CC-08 tiene puente Reown AppKit/WalletConnect y ejecutor móvil para depósito, cancelación y expiración, con persistencia de hash pendiente y conciliación API. El Project ID Reown del equipo no está configurado en el entorno local; por eso todavía no se verificó una transacción firmada desde el teléfono.
- El seed `app.devtools.seed_f09_demo` crea datos locales reproducibles. Sus wallets se insertan como fixture y **no prueban** las firmas EIP-191 de vinculación; se usan solo para avanzar por UI/reserva.
- El contrato API general `docs/api/catalog-reservations-v1.md` sigue etiquetado como **PROPUESTA**; mantener ese estado hasta revisión explícita.
- CC-09 está parcialmente verificada: suites, Docker, migraciones y build Android pasaron; falta recorrido móvil on-chain con Reown, salidas integradas y cierre documental. Los resultados históricos de `cliente-catalog.md` no se reutilizan como evidencia actual.
- F09.7 es condicional: no iniciar despliegue a testnet ni usar fondos/red pública sin confirmación del docente y autorización expresa. Hardhat local continúa siendo el entorno del plan.
- La configuración vigente de producto soporta `BOB`, `USD` y `USDT`; el depósito se configura por inmueble y se convierte a unidades del token de acuerdo con su escala. No reintroducir COP como moneda vigente ni derivar el depósito del precio de la oferta.

## 2. Alcance propuesto

### Incluido

1. **F09.1–F09.3 — Confirmación documental y brechas:** cotejar estados, plazos, restricciones e invariantes reales con las reglas de producto; revisar idempotencia, unicidad de reserva activa, snapshot comercial, permisos y replay. Registrar diferencias sin alterar requisitos canónicos ni el contrato API por inferencia.
2. **F09.4 / CC-07 — Experiencia cliente:** completar por capas sesión/wallet, cliente HTTP, repositorios, modelos y ViewModels; añadir cotización con moneda seleccionada, desglose autoritativo del servidor y estados de reserva. Reutilizar el catálogo real; no mostrar fixtures como datos reales.
3. **F09.4 / CC-08 — Flujo wallet:** Reown AppKit/WalletConnect está integrado para conectar una wallet EVM, firmar y enviar transacciones al Hardhat local; el Project ID público sigue pendiente. Verificar rechazo, cambio de cuenta/red, retorno a la app y reintentos sin duplicar depósitos. RoomForge nunca almacena claves privadas.
4. **F09.5 — Conciliación:** integrar el hash informado por las superficies con el verificador existente; mostrar “pendiente de verificar” hasta validar receipt/evento. Reproducir y probar fallos RPC, hash inválido, receipt revertido, evento incorrecto, replay e idempotencia.
5. **F09.6 — Vencimiento y salidas:** comprobar reembolso por rechazo/cancelación/vencimiento y liberación según el comportamiento del contrato actual; probar reserva aceptada, bloqueo del inmueble y límites de resolución posterior. No inventar liberación/reapertura de reservas aceptadas.
6. **F09.7:** preparar únicamente una evaluación de viabilidad documental de testnet (docente, red, RPC, faucet, wallet y costos). La implementación/despliegue queda fuera hasta recibir autorización.
7. **CC-09 — Verificación integrada:** ejecutar suites backend, Flutter y Hardhat, lint/tipos, build Android y migraciones PostgreSQL desechables; realizar un recorrido local reproducible y documentar límites de emulador/dispositivo.

### Excluido

Fondos reales, testnet sin autorización, custodia/relayer, indexador general, garantías de finality/reorg fuera de Hardhat, pagos de compraventa/alquiler, desbloqueo automático de una reserva aceptada y cambios de alcance del contrato API no aprobados.

## 3. Secuencia de trabajo y entregas

| Unidad | Trabajo | Entrega / condición para continuar |
|---|---|---|
| F09-P0 | Baseline del checkout, manifiestos, árbol de rutas, contrato Solidity/ABI, chain config, variables y estado de migraciones; consultar suite y tareas existentes. | Informe de baseline actual, diferencias entre documentos y código, sin mutaciones de entorno. |
| F09-P1 | Revisar decisiones y cerrar exclusivamente ambigüedades que bloqueen UI o transacciones. | Registro de decisiones confirmadas/pedientes; nada de asumir importes, SDK, red o UX de recuperación. |
| F09-P2 | CC-07: cotización y UI de solicitud/seguimiento sobre APIs ya existentes, primero con pruebas y estados de error/carga/offline. | Flujo funcional sin wallet transaccional, con snapshots/totales del servidor y sesión autenticada. |
| F09-P3 | CC-08: spike comparativo del SDK/protocolo; elegir solo tras demostrar soporte en Android/Flutter y compatibilidad con Hardhat local. Implementar firma/envío y retorno. | Depósito, decisión y reembolso end-to-end en Hardhat; captura de errores y no duplicación. |
| F09-P4 | CC-09: pruebas integradas, migración PostgreSQL desechable y recorrido manual. | Registro de comandos/resultados observados, evidencias autorizadas y límites pendientes. |
| F09-P5 | Actualización de estado F09 en plan maestro y cierre del registro de tarea. | Estado por subfase consistente con evidencia; F09.7 queda condicional si no hay decisión de testnet. |

Cada unidad se ejecuta en una rama propia desde `main` actualizado según las convenciones del repositorio; serializar cambios compartidos en `apps/cliente_mobile/` y cualquier migración. No crear migraciones salvo que el diseño aprobado las necesite. No editar `docs/diagramas/Diagrama1.eapx`.

## 4. Lecturas y comprobaciones antes de implementar

- Revisar `AGENTS.md`, este plan maestro §1.4.1/§1.4.4/F09, redefinición §4 y §6, `odd/tasks/cliente-catalog.md`, `docs/api/catalog-reservations-v1.md`, `contracts/README.md` y los manifiestos actuales.
- Inspeccionar rutas reales en `backend/app/modules/reservations/`, `backend/app/modules/catalog/`, configuración de cadena, esquema/ABI y pruebas existentes. Verificar la cadena Alembic real antes de crear cualquier revisión nueva.
- Baseline desde las carpetas respectivas: backend `pytest tests -q`, Ruff y Pyright usando el intérprete raíz; `contracts`: `npm test`; app cliente: `flutter test`, `flutter analyze` y build Android debug. Registrar el estado previo; no describir evidencia histórica como corrida actual.
- Verificación de base PostgreSQL únicamente en una base desechable y con configuración/credenciales autorizadas. No limpiar contenedores, volúmenes ni bases existentes.

## 5. Decisiones que deben confirmarse para CC-07/CC-08

1. **Wallet Flutter:** Reown AppKit/WalletConnect quedó seleccionado e integrado con el esquema local `eip155:31337`. Falta un Project ID público del equipo y validar retorno desde la wallet Android elegida. Sin ese dato, limitar la prueba al flujo hasta reserva; no simular firma ni depósito.
2. **Depósito tras aceptación:** el registro F05/F09 y el contrato actual describen liberación a la wallet de agencia al aceptar. Confirmar que esta salida sigue siendo la regla de producto vigente antes de exponerla como resultado final en UI; la redefinición original mantenía ese punto pendiente.
3. **Reservas aceptadas no cerradas legalmente:** no hay cancelación automática acordada. Antes de agregar reapertura o devolución excepcional, solicitar una decisión de producto; el plan actual no autoriza esa extensión.
4. **Testnet:** requiere confirmación del docente, red/RPC y autorización humana separada. Hasta entonces, solo Hardhat local y evidencias rotuladas como locales.

## 6. Criterios de cierre de F09

- Un cliente autenticado consulta oferta/cotización actual y ve importe, moneda, depósito y estado con datos del servidor.
- Wallet externa vinculada firma/transmite desde la cuenta esperada; rechazo, cambio de cuenta/red o timeout no produce una reserva falsamente confirmada ni un segundo depósito por reintento.
- La API solo declara resultado on-chain tras validar receipt y evento con el contrato/red local configurados; el procesamiento repetido conserva idempotencia y auditoría.
- Pruebas comprueban competencia por el mismo inmueble, snapshot, expiración, rechazo, cancelación, aceptación, reembolso/liberación según las reglas acordadas, replay y fallos de cadena.
- Suites y comprobaciones aplicables pasan en el checkout de cierre; las migraciones se verifican hasta head contra PostgreSQL desechable si hubo cambios de esquema.
- Se actualizan §1.4.1 y el estado F09 del plan maestro únicamente con resultados ejecutados. F09.7 permanece pendiente si no se autoriza testnet.

**Estado de asignación:** ☒ En curso en `develop`; integrar el estado de esta fase en `main` sin marcar cierre hasta terminar las comprobaciones pendientes.
**Estado de decisiones:** el usuario confirmó que, al aceptar la reserva, el depósito se transfiere a la wallet verificada de la agencia. Mantener F09.7/testnet fuera de alcance sin autorización.

## 7. Reanudación y evidencia actual

- Se reanuda desde cambios locales existentes; no se descarta ni sobrescribe trabajo previo.
- Tras la integración de F04 y la corrección de reconexión de wallet, `flutter test` pasó con 98 tests; `flutter analyze` pasó sin problemas.
- Backend: `pytest tests -q` pasó con 660 tests y 3 omitidos; Ruff y Pyright pasaron. El seed F09 también pasa Ruff/Pyright.
- Hardhat: `npm test` pasó con 40 pruebas. `npm run deploy:local` despliega RFT, MockUSDT y dos escrows; la API firmó un permiso EIP-712 BOB contra el RPC local.
- Docker: los cinco servicios (PostgreSQL, Floci, API, panel y Hardhat) están en un único stack y llegaron a `healthy`. La imagen backend incluye `alembic.ini`/`alembic/`; la base local está en `0018_listing_photos (head)`.
- `app.devtools.seed_f09_demo` sembró idempotentemente el listing `f09-demo-listing` en BOB (precio `250000.00`, depósito `10.00`) y wallets de prueba para dos cuentas cliente distintas. En el Samsung, `GET /api/v1/listings` devolvió 200, `POST /api/v1/quotes` devolvió 201 y `POST /api/v1/reservations` devolvió 201; PostgreSQL confirmó estado `pending` y `deposit_confirmed_at` nulo.
- El APK debug con las direcciones/API locales se compiló e instaló en el Samsung. `adb reverse` enlaza 8000/8545/4566.
- Pendiente: el seed wallet omite EIP-191; falta el Project ID Reown para conectar la wallet real de prueba y verificar desde el teléfono firma, depósito, receipt, evento y conciliación. Aceptación/rechazo/reembolso están cubiertos en contrato/backend, pero falta recorrer esas salidas integradas. F09.7/testnet permanece condicional.
- Mantener F09 en desarrollo hasta completar el recorrido móvil on-chain, revisar la evidencia y actualizar formalmente el cierre. No aprobar el contrato API general ni afirmar que F09 está completa por las pruebas unitarias.

## 8. Evidencia 2026-10-22/23 (PR #57, #58 y #61)

- **Integración en `main` (`5f0905d`, PR #57 y #58):** backend `pytest` 868 passed / 8 skipped, Ruff y Pyright sin errores (Pyright requiere `--pythonpath` al intérprete del `.venv`); panel 181 pruebas; Flutter cliente 150; Hardhat 40. El PR #58 incorporó el depósito con tarjeta mediante Stripe, documentado en el plan como F09.8.
- **Salidas observadas en el escrow local (PR #61):** `backend/tests/test_reservation_hardhat_e2e.py` envía transacciones reales a un nodo Hardhat y las concilia por la API, verificando saldos del token: depósito y replay sin doble confirmación; aceptación con liberación a la wallet de la agencia; rechazo, cancelación del cliente y vencimiento (`evm_increaseTime`) con reembolso al cliente. Resultado local: 8 passed.
- **Fallos de cadena (PR #61):** transacción sin evento `Deposited` (el hash del `approve`), depósito minado revertido y nodo inalcanzable responden `422 chain_transaction_unverified` sin confirmar la reserva; al volver el nodo, el mismo hash se concilia.
- **CI (PR #61):** nuevo job `Contracts and chain seam (Hardhat)` que corre las pruebas del contrato, levanta un nodo, despliega el escrow y ejecuta las pruebas anteriores en cada PR.
- **Invariantes ya cubiertas por pruebas del backend:** bloqueo por inmueble (`test_active_listing_lock_reusable_quote_and_unpaid_deadline_expiry`), snapshot (`test_create_snapshots_quote_deposit_and_both_linked_wallet_addresses`), idempotencia (`test_idempotency_replays_same_body_and_rejects_key_reuse_with_different_body`) y replay (`test_customer_reconciles_deposit_atomically_and_replays_without_duplicate_audit`). Límite: el bloqueo se prueba con solicitudes secuenciales, no con una carrera simultánea real.
- **Contrato API:** revisado contra el OpenAPI generado; `docs/api/catalog-reservations-v1.md` registra la revisión del 2026-10-23, las rutas faltantes y las decisiones resueltas. **Decisión del usuario (2026-10-23): aprobado con observaciones**; quedan abiertas la falta del sobre de error común en las rutas de Stripe y las decisiones D-07, D-10, D-12 y D-20.
- **Pendiente para el cierre:** Project ID de Reown y depósito firmado desde la wallet del teléfono con sus negativos (issue #27); recorrido manual de Stripe con cuenta de prueba (F09.8). Prueba de mutación del evento `Accepted` sin ejecutar. F09.7/testnet sigue condicional.
