# Infraestructura local

Este stack de desarrollo inicia PostgreSQL, Floci, la API FastAPI real y el panel `panel/staff-shell`. No inicia worker, aplicaciones móviles ni contratos. Floci emula S3/SQS para pruebas locales; no es un despliegue en AWS ni ofrece paridad completa con AWS.

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
| Panel staff-shell | `http://127.0.0.1:5173` (`PANEL_PORT`) | `5173` |

Dentro de Compose, la API se conecta a PostgreSQL por el hostname `postgres` y recibe los endpoints de Floci por `http://floci:4566`. El proxy Vite del panel apunta a `http://api:8000`; al ejecutar Vite directamente en el host, su valor por defecto existente sigue siendo `http://127.0.0.1:8000`. La plantilla contiene secretos ficticios solo para desarrollo local; Compose fija credenciales AWS de prueba (`local-test-key`/`local-test-secret`) y nunca debe recibir credenciales reales.

## Salud del stack, API y panel

Compose define healthchecks para los cuatro servicios:

- PostgreSQL ejecuta `pg_isready`.
- Floci consulta `aws s3api list-buckets`.
- La API solicita `/openapi.json`, ejecuta `SELECT 1` en PostgreSQL y comprueba conectividad TCP con Floci.
- El panel comprueba que la raíz de Vite responda con HTTP exitoso.

La API espera a que PostgreSQL y Floci estén saludables; el panel espera a que la API esté saludable. El healthcheck del panel valida Vite, mientras que la condición de dependencia ordena su inicio después de la API.

Consultar el estado de los servicios y probar las respuestas HTTP desde PowerShell:

```powershell
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml ps
Invoke-WebRequest -Uri http://127.0.0.1:8000/openapi.json -UseBasicParsing
Invoke-WebRequest -Uri http://127.0.0.1:5173/ -UseBasicParsing
```

Se espera que los cuatro servicios figuren como `healthy` y que ambas solicitudes HTTP tengan éxito. La API comprueba conectividad con Floci, pero esto no demuestra operaciones S3/SQS ejecutadas por la aplicación.

Para reducir el consumo local cuando no se necesita la API ni el panel, se puede iniciar solo PostgreSQL y Floci:

```powershell
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml up -d postgres floci
```

Si API o panel ya estuvieran ejecutándose, se pueden detener sin parar las dependencias:

```powershell
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml stop api panel
```

### Aprovisionar recursos S3 y SQS

La plantilla define el bucket `roomforge-local-assets` y la cola `roomforge-local-events`. `S3_ENDPOINT_URL` y `SQS_ENDPOINT_URL` usan `http://floci:4566`, accesible para clientes conectados a la red de Compose; desde el host, Floci se alcanza en `http://127.0.0.1:4566`.

Con Floci ya iniciado y en estado `healthy`, ejecutar desde la raíz:

```powershell
.\infra\docker\init-local-resources.ps1
```

El script consulta primero S3 y SQS con AWS CLI dentro del contenedor Floci. Solo crea el bucket o la cola configurados si no existen; repetirlo deja intactos los recursos existentes. Si una consulta falla por servicio, autenticación o red, el proceso termina con error en lugar de interpretar el fallo como un recurso ausente. No inicia ni detiene servicios y no elimina recursos.

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
