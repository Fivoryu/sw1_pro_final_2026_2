# F09 — Guía para completar la fase (traspaso)

Esta guía permite que otra persona del equipo cierre la fase F09 (reservas y contrato inteligente). El código está integrado y verificado de forma automática; el depósito local ya fue observado con MetaMask y conciliado por la API, pero quedan negativos de wallet, el recorrido manual de Stripe y el cierre documental. El registro histórico de ejecución está en `odd/tasks/f09-reservations-completion.md` y el contrato API en `docs/api/catalog-reservations-v1.md`.

> **Estado actual:** F09 sigue 🟡 parcial. El depósito observado no cierra la issue #27 ni toda la fase. El recorrido manual de Stripe está **pausado por decisión explícita del usuario** porque consume demasiado tiempo; no reanudarlo ni reintentarlo sin nueva solicitud.

## Qué falta

| # | Tarea | Issue | Criterio de cierre |
|---|---|---|---|
| A | Negativos y cierre del depósito desde la wallet real del teléfono | #27 | El depósito ya fue observado: MetaMask confirmó aprobación RFT y depósito, la API reconcilió receipt/evento con HTTP 200, estableció `deposit_confirmed_at` y la UI ocultó el botón de repetir. Quedan rechazo, cuenta/red incorrecta, receipt perdido, replay y cancelación. |
| B | Recorrido manual de Stripe con cuenta de prueba (**pausado**) | F09.8 (sin issue) | PaymentSheet, Connect, webhook, transferencia, reembolso y reenvío idempotente permanecen pendientes por decisión explícita del usuario. |
| C | Cierre documental | — | Plan maestro, registro ODD e issues actualizados con la evidencia de A y B. |

La issue #28 queda cumplida con el PR #61 (salidas observadas en el escrow local y contrato API aprobado con observaciones) y se cierra al hacer merge. Si el PR aún no está integrado, integrarlo antes de empezar.

## Qué ya está hecho

| Área | Estado y evidencia |
|---|---|
| Backend de reservas | Estados, bloqueo por inmueble, snapshot, idempotencia, permisos EIP-712 y conciliación de receipts/eventos. |
| Escrow (`contracts/`) | `ReservationEscrow.sol` con RFT y MockUSDT en Hardhat `31337`; 40 pruebas. |
| Integración backend ↔ escrow | `backend/tests/test_reservation_hardhat_e2e.py`: depósito, aceptación (libera a la agencia), rechazo, cancelación y vencimiento (reembolsan), evento incorrecto, receipt revertido y nodo caído, contra un nodo real. Corre en CI en el job `Contracts and chain seam (Hardhat)`. |
| App cliente | Cotización, solicitud y seguimiento de reservas; depósito local por WalletConnect (Reown AppKit) observado con conciliación. El pago con tarjeta (`flutter_stripe`) está implementado, pero su recorrido manual permanece pendiente y pausado. |
| Panel | Interfaz para iniciar el onboarding de Stripe Connect y decisiones de reservas **con tarjeta**; la habilitación real de Connect no se completó ni verificó. |
| Contrato API | Aprobado con observaciones el 2026-10-23. |

## Requisitos

- Windows con Docker Desktop, el `.venv` de la raíz, Node 22 y Flutter (comandos de Flutter desde PowerShell).
- Un teléfono Android conectado por USB con depuración activada **y con internet**: WalletConnect usa el relay en la nube de Reown aunque la cadena sea local.
- Para la tarea A: una cuenta gratuita en [dashboard.reown.com](https://dashboard.reown.com) y una wallet móvil que admita redes personalizadas (por ejemplo, MetaMask).
- Para la tarea B: una cuenta de Stripe en **modo de prueba** y la [Stripe CLI](https://docs.stripe.com/stripe-cli).
- Ningún secreto se versiona: Project ID, claves de Stripe y secreto del webhook van en un archivo de entorno **fuera del repositorio**.

## 1. Entorno local

El stack local levanta PostgreSQL, Floci, la API, el panel y un nodo Hardhat que despliega el escrow solo, con las mismas direcciones que espera la API.

```powershell
# Copiar el ejemplo fuera del repositorio y completar las claves de Stripe (tarea B)
Copy-Item infra\docker\local-env.example $env:USERPROFILE\roomforge-f09.env

docker compose --env-file $env:USERPROFILE\roomforge-f09.env -f infra/docker/compose.local.yml up -d --build
docker compose --env-file $env:USERPROFILE\roomforge-f09.env -f infra/docker/compose.local.yml ps
```

Los cinco servicios deben quedar `healthy`. Direcciones del despliegue local (deterministas en un nodo nuevo):

| Contrato | Dirección |
|---|---|
| RFT (BOB/USD, 2 decimales) | `0x5FbDB2315678afecb367f032d93F642f64180aa3` |
| MockUSDT (6 decimales) | `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512` |
| Escrow BOB/USD | `0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0` |
| Escrow USDT | `0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9` |

## 2. Datos de prueba

1. **Administrador de plataforma:** seguir `backend/README.md` («Initial platform administrator»). En el stack local la invitación llega al buzón de desarrollo (`app.core.dev_email`).
2. **Cliente:** registrarse desde la app cliente con un correo de prueba.
3. **Inmueble y wallets:** con `ROOMFORGE_ALLOW_LOCAL_DEMO_SEED=true` en el archivo de entorno (ya viene así en el ejemplo):

```powershell
docker compose --env-file $env:USERPROFILE\roomforge-f09.env -f infra/docker/compose.local.yml exec api `
  python -m app.devtools.seed_f09_demo --customer-email <correo-del-cliente>
```

El seed crea el inmueble `f09-demo-listing` (BOB 250000.00, depósito BOB 10.00) y vincula las wallets **sin firma EIP-191**: es un atajo local. El cliente queda con la cuenta Hardhat #1 y la agencia con la #2:

| Rol | Cuenta Hardhat | Dirección | Clave privada (pública, solo para Hardhat local) |
|---|---|---|---|
| Cliente | #1 | `0x70997970c51812dc3a010c7d01b50e0d17dc79c8` | `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d` |
| Agencia | #2 | `0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc` | `0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a` |

Estas claves son las de prueba que publica Hardhat; nunca usarlas en una red pública ni enviarles fondos reales.

## 3. Tarea A — Wallet real desde el teléfono (#27)

### Preparación

1. Crear un proyecto en dashboard.reown.com y copiar su **Project ID**.
2. En la wallet del teléfono: importar la cuenta del cliente (#1) con su clave privada y agregar una red personalizada con RPC `http://127.0.0.1:8545`, chain ID `31337` y moneda `ETH`. Importar el token RFT (`0x5FbDB2315678afecb367f032d93F642f64180aa3`, 2 decimales) para ver el saldo.
3. Compilar e instalar la app cliente apuntando al stack local por túneles USB:

```powershell
cd apps\cliente_mobile
flutter.bat build apk --debug `
  --dart-define=ROOMFORGE_API_BASE_URL=http://127.0.0.1:8000 `
  --dart-define=ROOMFORGE_HARDHAT_RPC_URL=http://127.0.0.1:8545 `
  --dart-define=ROOMFORGE_REOWN_PROJECT_ID=<project-id> `
  --dart-define=ROOMFORGE_RFT_ADDRESS=0x5FbDB2315678afecb367f032d93F642f64180aa3 `
  --dart-define=ROOMFORGE_ESCROW_BOB_ADDRESS=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 `
  --dart-define=ROOMFORGE_ESCROW_USD_ADDRESS=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 `
  --dart-define=ROOMFORGE_USDT_ADDRESS=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 `
  --dart-define=ROOMFORGE_ESCROW_USDT_ADDRESS=0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
adb install -r build\app\outputs\flutter-apk\app-debug.apk
adb reverse tcp:8000 tcp:8000   # API
adb reverse tcp:8545 tcp:8545   # Hardhat (la wallet del teléfono también lo usa)
```

`local-env.example` trae `ROOMFORGE_HARDHAT_RPC_URL=http://10.0.2.2:8545`, que sirve para el **emulador**; con un teléfono físico y `adb reverse` se usa `127.0.0.1`. Los túneles se pierden al desconectar el teléfono.

### Recorrido y resultados esperados

| Paso | Resultado esperado |
|---|---|
| Cotizar `f09-demo-listing` y solicitar la reserva | Reserva `pending`, depósito BOB 10.00 y aviso de que pendiente no es depósito confirmado. |
| Conectar la wallet y depositar | La wallet pide aprobar el token y luego el depósito; al volver a la app, la reserva muestra el depósito confirmado y el saldo RFT del cliente baja 1000 unidades. |
| Rechazar la firma en la wallet | La app muestra el error; la reserva sigue sin depósito y no queda transacción enviada. |
| Cambiar de cuenta o de red en la wallet antes de firmar | La app no opera con la sesión equivocada; no hay depósito. |
| Perder el receipt (por ejemplo, cortar el túnel 8545 justo después de firmar) | La app avisa que no hay recibo y que **no hay que reenviar**; al reconectar y actualizar, concilia el mismo hash. |
| Reintentar el depósito ya hecho | No se produce un segundo depósito; la API responde con el mismo resultado (`replayed`). |
| Cancelar como cliente (con otra reserva) | Reembolso al cliente y estado `cancelled`. |

Para comprobar el escrow sin la app, consultar el saldo RFT del escrow con `eth_call` a `balanceOf(0x9fE4…a6e0)` contra `http://127.0.0.1:8545`.

**Evidencia a registrar** en `odd/tasks/f09-reservations-completion.md`: modelo del teléfono y de la wallet, hashes de las transacciones, respuesta de la API (`event_name`, `status`, `replayed`), saldos antes y después, y el resultado de cada negativo.

## 4. Tarea B — Stripe en modo de prueba (F09.8) — **PAUSADA**

El recorrido manual queda pendiente por decisión explícita del usuario. `stripe tools enable_connect` no tuvo éxito: aunque el proceso terminó con exit 0, el JSON indicó `request_failed` porque la clave no tenía acceso a la cuenta objetivo; no se creó una cuenta conectada ni un Account Link. El intento de sandbox claimable quedó sin verificar y abrió un fallback de login/autorización; se indicó no aprobarlo ni ingresar credenciales porque la ruta podía usar una cuenta live. No hay sandbox confirmado ni operación/dato real involucrado. No ejecutar ni reintentar esta tarea hasta que el usuario lo solicite explícitamente.

1. En el archivo de entorno: `STRIPE_SECRET_KEY=sk_test_…` y `STRIPE_PUBLISHABLE_KEY=pk_test_…` (la API rechaza claves que no sean de prueba).
2. Reenviar los webhooks a la API local y copiar el `whsec_…` que imprime en `STRIPE_WEBHOOK_SECRET`; recrear el contenedor `api`:

```powershell
stripe listen --forward-to localhost:8000/api/v1/stripe/webhook
docker compose --env-file $env:USERPROFILE\roomforge-f09.env -f infra/docker/compose.local.yml up -d api
```

3. **Agencia:** el administrador de plataforma invita a un `agency_admin` de `f09-demo-agency` desde el panel; ese usuario abre «Pagos con tarjeta» y completa el alta de Stripe Connect con los datos de prueba de Stripe.
4. **Cliente:** en la app, solicitar una reserva con pago con tarjeta y pagar con la tarjeta de prueba `4242 4242 4242 4242` (cualquier fecha futura y CVC).

| Paso | Resultado esperado |
|---|---|
| Pago con tarjeta | `stripe listen` muestra `payment_intent.succeeded`; la reserva queda con el depósito confirmado. |
| Aceptar desde el panel | Transferencia a la cuenta Connect (visible en el dashboard de Stripe); reserva `accepted`. |
| Rechazar desde el panel (otra reserva) | Reembolso visible en Stripe; reserva `rejected`. |
| Reenviar el mismo evento (`stripe events resend <id>`) | Sin efectos dobles. |

Registrar los IDs de PaymentIntent, transferencia y reembolso en el registro ODD.

## 5. Huecos conocidos y decisiones abiertas

- **El panel no decide reservas con wallet.** Solo las con tarjeta. Aceptar o rechazar una reserva con wallet se hace por API (`POST /api/v1/staff/reservations/{id}/permit` y luego `…/chain-transactions`), como en `test_reservation_hardhat_e2e.py`. Las issues no exigen esa interfaz; si el equipo la quiere para la demo, es alcance nuevo: primero se actualiza el plan maestro y después se abre la issue.
- **Errores de Stripe:** sus rutas responden `{"detail": …}` y no el sobre común `{code, message, request_id}` (observación de la aprobación del contrato).
- **Concurrencia real:** el bloqueo por inmueble está probado con solicitudes secuenciales, no con dos clientes en simultáneo.
- **Prueba de mutación pendiente:** cambiar `Accepted` por `Approved` en `ReservationEscrow.sol`; el test de aceptación del job de CI debe fallar. Revertir después.
- **F09.7 (testnet):** fuera de alcance sin autorización del docente.

## 6. Cierre de la fase

- [ ] Negativos restantes de wallet y evidencia completa de A registrados en `odd/tasks/f09-reservations-completion.md`.
- [ ] Recorrido Stripe de B y su evidencia: **pausados**, no completados.
- [ ] PR con `Closes #27` (no corresponde declararlo hasta completar los criterios restantes).
- [ ] Plan maestro: fila F09 de §1.4.1 en ✅ con la evidencia; F09.4 y F09.8 actualizadas en la sección F09; #27 y #28 movidas a «cerradas» en la tabla §1.4.5.
- [ ] Suites en verde en el CI del PR, incluido el job `Contracts and chain seam (Hardhat)`.
