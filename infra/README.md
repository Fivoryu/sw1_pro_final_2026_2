# Infraestructura local

Este stack de desarrollo inicia PostgreSQL, Floci, la API FastAPI real, el panel `panel/staff-shell` y un nodo Hardhat con los contratos locales de F09 desplegados. Las apps móviles se ejecutan en un emulador Android conectado a los puertos publicados del host. Floci emula S3/SQS para pruebas locales; no es un despliegue en AWS ni ofrece paridad completa con AWS.

## Requisitos

- Docker Desktop con Docker Compose disponible en PowerShell.
- Ejecutar los comandos siguientes desde la raíz del repositorio.

La plantilla `infra/docker/local-env.example` contiene únicamente valores ficticios para desarrollo local. No reemplazarlos por credenciales reales ni compartirlos como secretos. Compose usa un nombre de proyecto dedicado (`roomforge-local-dev`), por lo que los volúmenes persistentes de este stack quedan separados de otros proyectos.

## Iniciar

```powershell
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml up -d
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml ps
```

Los servicios se publican solo en loopback; los puertos del host se configuran en `infra/docker/local-env.example`:

| Servicio | Acceso desde el host | Puerto del contenedor |
| --- | --- | --- |
| PostgreSQL | `127.0.0.1:5434` (`POSTGRES_PORT`) | `5432` |
| Floci, S3/SQS local | `http://127.0.0.1:4566` (`FLOCI_PORT`) | `4566` |
| API FastAPI | `http://127.0.0.1:8000` (`API_PORT`) | `8000` |
| Hardhat RPC | `http://127.0.0.1:8545` (`HARDHAT_PORT`) | `8545` |
| Panel staff-shell | `http://127.0.0.1:5173` (`PANEL_PORT`) | `5173` |

Dentro de Compose, la API se conecta a PostgreSQL por el hostname `postgres` y recibe los endpoints de Floci por `http://floci:4566`. El proxy Vite del panel apunta a `http://api:8000`; al ejecutar Vite directamente en el host, su valor por defecto existente sigue siendo `http://127.0.0.1:8000`. La plantilla contiene secretos ficticios solo para desarrollo local; Compose fija credenciales AWS de prueba (`local-test-key`/`local-test-secret`) y nunca debe recibir credenciales reales. Para verificar la app móvil desde un teléfono en la misma red, `API_BIND_ADDRESS=0.0.0.0` publica la API en la interfaz LAN; por defecto queda solo en loopback y no expone nada fuera del equipo. Ojo con dos cosas más: si la Wi-Fi tiene **aislamiento de clientes** el teléfono no alcanza al host aunque estén en la misma subred, y el enlace de subida se firma con `S3_PUBLIC_ENDPOINT_URL` (`http://127.0.0.1:4566` por defecto), así que la prueba por USB necesita **los dos** túneles, `adb reverse tcp:8000` y `adb reverse tcp:4566`; sin el segundo la subida se queda esperando y no muestra ningún error.

Hardhat comparte el namespace de red del contenedor `api`. Así la API usa `http://127.0.0.1:8545` (RPC de loopback validado por el backend), mientras Docker publica el nodo en el host/emulador. Al arrancar, Hardhat despliega RFT, MockUSDT y ambos escrows con direcciones deterministas. Todos los fondos y claves son de desarrollo local.

## Salud del stack, API y panel

Compose define healthchecks para los cinco servicios:

- PostgreSQL ejecuta `pg_isready`.
- Floci consulta `aws s3api list-buckets`.
- La API solicita `/openapi.json`, ejecuta `SELECT 1` en PostgreSQL y comprueba conectividad TCP con Floci.
- El panel comprueba que la raíz de Vite responda con HTTP exitoso.
- Hardhat comprueba que JSON-RPC responda con `chainId` 31337.

La API espera a que PostgreSQL y Floci estén saludables; el panel espera a que la API esté saludable. Hardhat comparte la red de la API y espera a que su contenedor inicie; su propio healthcheck comprueba la disponibilidad del RPC. El healthcheck del panel valida Vite.

Consultar el estado de los servicios y probar las respuestas HTTP desde PowerShell:

```powershell
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml ps
Invoke-WebRequest -Uri http://127.0.0.1:8000/openapi.json -UseBasicParsing
Invoke-WebRequest -Uri http://127.0.0.1:5173/ -UseBasicParsing
```

Se espera que los cinco servicios figuren como `healthy` y que las solicitudes HTTP tengan éxito. La API comprueba conectividad con Floci, pero esto no demuestra operaciones S3/SQS ejecutadas por la aplicación.

### Migrar la base y ejecutar el cliente Android

La imagen de la API no ejecuta migraciones automáticamente. Con Compose iniciado, aplicar la cadena completa en PostgreSQL local:

```powershell
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml exec -T api python -m alembic upgrade head
```

Comprobar que la API quedó lista y que Hardhat respondió:

```powershell
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml ps
Invoke-WebRequest -Uri http://127.0.0.1:8000/health/ready -UseBasicParsing
Invoke-RestMethod -Uri http://127.0.0.1:8545 -Method Post -ContentType 'application/json' -Body '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}'
```

Para ejecutar el cliente en un emulador Android, abrir un terminal en `apps/cliente_mobile/` y pasar las URLs/direcciones de `local-env.example` como dart-defines. Reown requiere el Project ID público del equipo:

```powershell
flutter run `
  --dart-define=ROOMFORGE_API_BASE_URL=http://10.0.2.2:8000 `
  --dart-define=ROOMFORGE_HARDHAT_RPC_URL=http://10.0.2.2:8545 `
  --dart-define=ROOMFORGE_RFT_ADDRESS=0x5FbDB2315678afecb367f032d93F642f64180aa3 `
  --dart-define=ROOMFORGE_USDT_ADDRESS=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 `
  --dart-define=ROOMFORGE_ESCROW_BOB_ADDRESS=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 `
  --dart-define=ROOMFORGE_ESCROW_USD_ADDRESS=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 `
  --dart-define=ROOMFORGE_ESCROW_USDT_ADDRESS=0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9 `
  --dart-define=ROOMFORGE_REOWN_PROJECT_ID=ID_PUBLICO_DEL_EQUIPO
```

El nodo muestra las cuentas de prueba al arrancar. Importarlas solo en una wallet conectada a la red local `31337`; no usar esas claves en redes públicas ni con fondos reales. Sin Project ID Reown, catálogo/cuenta siguen ejecutables, pero WalletConnect queda deshabilitado.

### Cargar datos demo para F09

Después de registrar la cuenta de cliente en el teléfono, se puede preparar un inmueble local para probar cotización y solicitud de reserva:

```powershell
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml exec -T api python -m app.devtools.seed_f09_demo --customer-email TU_CORREO_DE_CLIENTE
```

El seed es idempotente: crea `f09-demo-agency`, un inmueble BOB publicado con precio `250000.00` y depósito `10.00`, y asocia las wallets de prueba de Hardhat al cliente y a la agencia si aún no tienen una. **Enlaza las wallets directamente en la base local sin verificar firmas** para facilitar la demostración; no usar fuera del entorno local. La bandera `ROOMFORGE_ALLOW_LOCAL_DEMO_SEED=true` de `local-env.example` habilita explícitamente el comando.

Si hay más de una cuenta cliente local, asignar la wallet de prueba secundaria (Hardhat account #3) a otra cuenta para respetar la unicidad de direcciones:

```powershell
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml exec -T api python -m app.devtools.seed_f09_demo --customer-email TU_CORREO_DE_CLIENTE --customer-wallet-address 0x90F79bf6EB2c4f870365E785982E1f101E93b906
```

Después del seed, cierra sesión y vuelve a entrar en la app para que recargue la wallet demo. En **Explorar**, abre el inmueble, cotiza en BOB y solicita la reserva; aparecerá en **Reservas**. Para probar el depósito on-chain real aún debes configurar un Project ID Reown y conectar desde el teléfono la cuenta cliente de prueba del nodo Hardhat. El nodo entrega tokens de prueba a esa cuenta; nunca uses cuentas ni fondos reales.

Para reducir el consumo local cuando no se necesita la API ni el panel, se puede iniciar solo PostgreSQL y Floci:

```powershell
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml up -d postgres floci
```

Si API o panel ya estuvieran ejecutándose, se pueden detener sin parar las dependencias:

```powershell
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml stop api hardhat panel
```

### Aprovisionar recursos S3 y SQS

La plantilla define el bucket `roomforge-local-assets` y la cola `roomforge-local-events`. `S3_ENDPOINT_URL` y `SQS_ENDPOINT_URL` usan `http://floci:4566`, accesible para clientes conectados a la red de Compose; desde el host, Floci se alcanza en `http://127.0.0.1:4566`.

Con Floci ya iniciado y en estado `healthy`, ejecutar desde la raíz:

```powershell
.\infra\docker\init-local-resources.ps1
```

El script consulta primero S3 y SQS con AWS CLI dentro del contenedor Floci. Solo crea el bucket o la cola configurados si no existen; repetirlo deja intactos los recursos existentes. Si una consulta falla por servicio, autenticación o red, el proceso termina con error en lugar de interpretar el fallo como un recurso ausente. No inicia ni detiene servicios. También aplica la regla de ciclo de vida del staging que se describe abajo, sin reemplazar las reglas ajenas que ya tenga el bucket.

### Ciclo de vida del staging de fotografías

Los objetos de staging de F04.2 viven bajo el prefijo de primer nivel `staging/` — `staging/agencies/<agencia>/listings/<inmueble>/photos/<foto>` —, separados del original privado y de la derivada pública, que **no** vencen. `set-staging-lifecycle.ps1` lee las reglas existentes, reemplaza solo la de ID `expire-listing-photo-staging` (o la agrega si falta) y conserva las demás al escribir `Rules` con `put-bucket-lifecycle-configuration`. Descarta campos de nivel superior que el `put` no admite; por ejemplo, el `get` de Floci incluye `TransitionDefaultMinimumObjectSize`. Trata `NoSuchLifecycleConfiguration` como una configuración sin reglas, para admitir el bucket recién creado. Con `-DryRun` imprime el JSON fusionado sin escribir; `-CurrentConfigurationJson` permite suministrar una configuración de prueba para ejercitar esa fusión sin consultar Floci.

El piso de S3 para `Days` es 1 día y el servicio puede tardar hasta unas 48 h en actuar, así que la regla **acota la retención** de cualquier objeto que se escape del barrido de la API; no cierra por sí sola la carrera de una subida en vuelo, que es lo que cubre la gracia del diario de borrado. En Floci la operación está implementada (`GetBucketLifecycleConfiguration` responde `NoSuchLifecycleConfiguration` cuando todavía no hay regla), pero un emulador prueba que acepta la configuración, no que borre sola. En el despliegue real la misma regla debe existir sobre el bucket de producción.

PostgreSQL conserva sus datos en el volumen nombrado `roomforge-local-dev_postgres_data`. Floci usa otro volumen nombrado, `roomforge-local-dev_floci_data`, montado en `/app/data`; su modo persistente y ruta se configuran mediante `FLOCI_STORAGE_MODE` y `FLOCI_STORAGE_PERSISTENT_PATH`. El prefijo corresponde al proyecto Compose: un nombre de proyecto distinto crea volúmenes separados sin reutilizar ni modificar los del stack habitual.

Para una futura comprobación aislada de persistencia, se puede usar el proyecto `roomforge-f01-verify` y puertos de host alternativos. En PowerShell, las variables de entorno prevalecen sobre los mismos valores del archivo `--env-file`:

```powershell
$env:POSTGRES_PORT = "55434"
$env:FLOCI_PORT = "14566"
$env:API_PORT = "18000"
$env:PANEL_PORT = "15173"
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml -p roomforge-f01-verify config --quiet
```

Ese proyecto usa volúmenes distintos (`roomforge-f01-verify_postgres_data` y `roomforge-f01-verify_floci_data`) y puertos que no colisionan con los valores predeterminados. Este ejemplo solo valida la configuración; no inicia servicios.

### Evidencia observada de F01-T3 (2026-09-26)

La verificación se ejecutó únicamente en el proyecto aislado `roomforge-f01-verify`, con los puertos alternativos indicados y sus propios volúmenes; el registro completo está en [la tarea F01](../odd/tasks/f01-infrastructure-completion.md). En el smoke de stack completo los cuatro servicios alcanzaron estado `healthy`. El proxy del panel llegó a FastAPI y una ruta desconocida devolvió el 404 JSON esperado.

Los marcadores `f01-persist-20260926` de PostgreSQL y SQS se observaron tras reiniciar sus servicios; el mensaje SQS se recibió y se dejó intencionalmente sin borrar. El objeto de 20 bytes `s3://roomforge-local-assets/f01/persistence-probe-20260926.txt` se cargó con `aws s3 cp`, se descargó y coincidió con el marcador antes y después del reinicio de Floci; Floci volvió a `healthy`. El inicializador `init-local-resources.ps1` también se ejecutó dos veces y dejó intactos el bucket y la cola ya existentes.

Desde Git Bash/MSYS, al pasar rutas Linux como `/tmp/...` al Docker CLI, hay que anteponer `MSYS_NO_PATHCONV=1` para evitar que MSYS las convierta en rutas de Windows. El upload real anterior se completó con `aws s3 cp`; no fue un `--dryrun`.

Al finalizar, los cuatro contenedores de prueba quedaron detenidos y se retuvieron intencionalmente `roomforge-f01-verify_floci_data` y `roomforge-f01-verify_postgres_data`, con los datos de prueba; no se ejecutó limpieza ni eliminación. `roomforge-local-dev` se observó detenido y no se operó durante la prueba. Una medición de Floci al final de la prueba de servicio único fue `38.37 MiB / 5.786 GiB`; es una observación puntual, no un objetivo ni una garantía de consumo.

Esta evidencia confirma probes/configuración y persistencia directa de datos en Floci, no operaciones S3/SQS a nivel de la aplicación FastAPI. Floci es emulación local, no AWS ni una garantía de paridad completa.

## Acceso local de personal

El backend no incluye un transporte de correo real. En este stack, el servicio `api` usa `STAFF_EMAIL_SENDER_FACTORY=app.core.dev_email:create_dev_outbox_sender`: cada invitación de personal (administrador de plataforma, administrador de agencia o agente) se guarda como un archivo JSON en `/tmp/roomforge-dev-outbox/` dentro del contenedor `api`, en lugar de enviarse por correo. El enlace contiene un token de un solo uso, por eso no se escribe en logs. El transporte se niega a cargar si `STAFF_WEB_ORIGIN` no es un origen local (`127.0.0.1` o `localhost`); no debe usarse fuera de desarrollo.

Crear el primer administrador de plataforma, con el stack iniciado:

1. Aplicar las migraciones (la imagen de la API no las ejecuta al arrancar). Desde `backend/`, con el entorno Python del proyecto:

   ```powershell
   $env:DATABASE_URL = "postgresql+psycopg://roomforge_local:local-postgres-only@127.0.0.1:5434/roomforge_local"
   ..\.venv\Scripts\python.exe -m alembic upgrade head
   ```

2. Emitir la invitación (sustituir el correo):

   ```powershell
   docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml exec -T api python -m app.modules.identity.bootstrap --email admin@example.test
   ```

3. Leer la invitación desde la bandeja de salida:

   ```powershell
   docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml exec -T api sh -c "cat /tmp/roomforge-dev-outbox/*.json"
   ```

4. Abrir el valor `link` en el navegador (`http://127.0.0.1:5173/invitations/accept/...`), definir la contraseña, registrar el código TOTP en una app autenticadora y guardar los códigos de recuperación.

Las invitaciones que después emita el panel o la API (administradores de agencia y agentes) llegan a la misma bandeja. Solo puede haber una invitación de administrador de plataforma pendiente a la vez. La bandeja vive en el sistema de archivos del contenedor: se pierde al recrearlo, así que conviene leer cada enlace al emitirlo.

## Comprobar PostgreSQL

El healthcheck de PostgreSQL usa `pg_isready`. También se puede ejecutar explícitamente y realizar una consulta SQL dentro del contenedor:

```powershell
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml exec -T postgres pg_isready -U roomforge_local -d roomforge_local
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml exec -T postgres psql -U roomforge_local -d roomforge_local -c "SELECT 1;"
```

Con los valores de plantilla, la cadena de conexión desde una herramienta instalada en el host es `postgresql://roomforge_local:local-postgres-only@127.0.0.1:5434/roomforge_local`.

## Comprobar Floci y probar S3/SQS

El healthcheck de Floci ejecuta `aws s3api list-buckets` desde la imagen `floci/floci:2.1.0-compat`, pasando explícitamente `FLOCI_ENDPOINT_URL`. Consultar el estado:

```powershell
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml ps
```

El servicio Floci debe aparecer como `healthy`. Los siguientes ejemplos ejecutan AWS CLI dentro del contenedor, por lo que no requieren AWS CLI instalado en Windows. El endpoint se pasa explícitamente en cada operación.

Crear y listar un bucket de prueba:

```powershell
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml exec -T floci aws --endpoint-url http://127.0.0.1:4566 s3api create-bucket --bucket roomforge-local-smoke
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml exec -T floci aws --endpoint-url http://127.0.0.1:4566 s3api list-buckets
```

Crear una cola, enviar un mensaje y recibirlo:

```powershell
$queueUrl = docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml exec -T floci aws --endpoint-url http://127.0.0.1:4566 sqs create-queue --queue-name roomforge-local-smoke --query QueueUrl --output text
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml exec -T floci aws --endpoint-url http://127.0.0.1:4566 sqs send-message --queue-url $queueUrl --message-body "mensaje de prueba local"
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml exec -T floci aws --endpoint-url http://127.0.0.1:4566 sqs receive-message --queue-url $queueUrl
```

Estos ejemplos crean recursos de prueba que permanecen en el almacenamiento persistente de Floci. El emulador facilita pruebas locales, pero no garantiza equivalencia completa con AWS ni debe considerarse un entorno de despliegue.

## Detener

Para detener los contenedores y conservarlos junto con sus datos, usar `stop`:

```powershell
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml stop
```

También se pueden quitar los contenedores y la red manteniendo los volúmenes nombrados:

```powershell
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml down
```

**No usar `down -v`**: los volúmenes guardan los datos persistentes de PostgreSQL y Floci.

## Referencias

- [Floci Quick Start](https://floci.io/floci/getting-started/quick-start/)
- [Floci 2.1.0](https://github.com/floci-io/floci/releases/tag/2.1.0)
- [Documentación oficial de Floci](https://github.com/floci-io/floci)
