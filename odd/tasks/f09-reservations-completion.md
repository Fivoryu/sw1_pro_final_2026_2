# F09 — Plan de cierre de reservas y contrato inteligente

**Estado:** en ejecución; registra evidencia observada al 12/10/2026, pero aún no acredita recorrido wallet completo ni aprobación del contrato API general.
**Fuentes canónicas:** `docs/plan-maestro-roomforge.md` (F09 y §1.4.1), `docs/redefinicion-roomforge.md` y las decisiones registradas en `odd/tasks/cliente-catalog.md`.
**Objetivo:** completar el recorrido de reserva ya respaldado por backend y escrow local, incorporar la experiencia real del cliente y registrar con claridad los límites de la cadena local.

## 1. Estado de partida contrastado

- F09.1–F09.6 tienen una base integrada: módulo backend `reservations`, migraciones hasta `0011_reservation_chain_txns`, permisos EIP-712, reconciliación de receipts/eventos y escrow Solidity con token de prueba/MockUSDT en Hardhat.
- El backend ya expone creación y lectura de reservas propias, emisión de permisos y reconciliación de transacciones. El contrato API general `docs/api/catalog-reservations-v1.md` sigue etiquetado como **PROPUESTA**; mantener ese estado hasta revisión explícita.
- CC-07 y CC-08 están pendientes: la app cliente aún necesita cotización, vinculación/uso de wallet y el recorrido UI→API→wallet→escrow.
- CC-09 requiere verificación integral actualizada. Los números de pruebas registrados en `cliente-catalog.md` son evidencia histórica de otros cortes, no resultados de esta ejecución.
- F09.7 es condicional: no iniciar despliegue a testnet ni usar fondos/red pública sin confirmación del docente y autorización expresa. Hardhat local continúa siendo el entorno del plan.
- La configuración vigente de producto soporta `BOB`, `USD` y `USDT`; el depósito se configura por inmueble y se convierte a unidades del token de acuerdo con su escala. No reintroducir COP como moneda vigente ni derivar el depósito del precio de la oferta.

## 2. Alcance propuesto

### Incluido

1. **F09.1–F09.3 — Confirmación documental y brechas:** cotejar estados, plazos, restricciones e invariantes reales con las reglas de producto; revisar idempotencia, unicidad de reserva activa, snapshot comercial, permisos y replay. Registrar diferencias sin alterar requisitos canónicos ni el contrato API por inferencia.
2. **F09.4 / CC-07 — Experiencia cliente:** completar por capas sesión/wallet, cliente HTTP, repositorios, modelos y ViewModels; añadir cotización con moneda seleccionada, desglose autoritativo del servidor y estados de reserva. Reutilizar el catálogo real; no mostrar fixtures como datos reales.
3. **F09.4 / CC-08 — Flujo wallet:** seleccionar un protocolo/SDK compatible con Flutter y verificable localmente; conectar la wallet externa vinculada, presentar red/cuenta/importe, obtener firma y permitir envío de transacciones; manejar rechazo, cambio de cuenta/red, retorno a la app y reintentos sin duplicar depósitos. RoomForge nunca almacena claves privadas.
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

1. **Wallet Flutter:** aprobar un SDK/protocolo candidato solo después del spike en Android y comprobar integración con las wallets disponibles. Si no existe retorno confiable a la app o soporte local, detener envío transaccional y presentar el bloqueo con evidencia; no sustituirlo por una simulación.
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

**Estado de asignación:** ☒ En curso en la rama `develop`; conservar los cambios locales existentes.
**Estado de decisiones:** el usuario confirmó que, al aceptar la reserva, el depósito se transfiere a la wallet verificada de la agencia. Mantener F09.7/testnet fuera de alcance sin autorización.

## 7. Reanudación y evidencia actual

- Se reanuda desde cambios locales existentes; no se descarta ni sobrescribe trabajo previo.
- Después de integrar F04 fotos desde `main`, `flutter test` pasó con 98 tests; incluye el fixture de sesión corregido (`access_expires_in`) y cobertura de catálogo con fotos.
- `flutter analyze` pasó sin problemas.
- `npm test` en `contracts/` pasó: 40 tests; compiló 26 archivos Solidity. Se añadió `npm run deploy:local` para desplegar RFT, MockUSDT y escrows en un nodo Hardhat persistente; se comprobó el script y la firma de un permiso contra RPC local.
- Backend después de integrar F04: `pytest tests -q` pasó con 660 tests y 3 omitidos; Ruff y Pyright pasaron (Pyright usando `--pythonpath ..\.venv\Scripts\python.exe`).
- Migración: una base PostgreSQL 16 desechable llegó a `0018_listing_photos (head)`; `test_f04_publications_postgres.py` pasó contra otra base recién creada y desechable. Se detuvo el contenedor creado para esta verificación.
- `flutter build apk --debug` pasó antes de sincronizar F04 desde `main`; el APK debe reconstruirse sobre este checkout combinado antes de usarlo como artefacto de prueba.
- El stack local no tenía API/PostgreSQL persistentes activos. No se ejecutó el recorrido manual Android→API→wallet externa→Hardhat→reconciliación. La WalletConnect real requiere un Project ID público de Reown y wallet de prueba configurados por el equipo; no se almacenan en el repositorio.
- `git diff --check` debe ejecutarse sobre los archivos preparados para commit. F09 permanece parcial hasta validar el recorrido con wallet externa y reconstruir el APK de la rama combinada. F09.7/testnet permanece excluida hasta autorización expresa.
