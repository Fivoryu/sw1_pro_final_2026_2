# F08.4 — Verificación contra infraestructura real

- **Fecha:** 2026-10-14 · **Rama:** `feat/f08-furniture-ai-pilot`
- **Alcance de este documento:** lo que se ejecutó **de verdad** contra PostgreSQL y Floci locales, con sus comandos y salidas. Todo lo demás de F08.4 se verificó con dobles y así se declara.
- **Entorno:** Docker Desktop 29.8.2 desde Windows; contenedores `postgres:16-alpine` y `floci/floci:2.1.0-compat` del stack local.

## 1. Migración `0019` contra PostgreSQL real

Antes de esto, la migración sólo se había probado contra SQLite en memoria. **Ese era un hueco real**, porque SQLite y PostgreSQL no se comportan igual.

Comando (la variable se fija **dentro del proceso**; ver hallazgo operativo 1):

```python
os.environ["DATABASE_URL"] = "postgresql+psycopg://roomforge_local:...@127.0.0.1:5434/roomforge_local"
command.upgrade(Config("alembic.ini"), "head")
```

Salida:

```
Running upgrade 0016_listing_extra_details -> 0017_exchange_rate_source
Running upgrade 0017_exchange_rate_source -> 0018_listing_photos
Running upgrade 0018_listing_photos -> 0019_detection_jobs
MIGRACION OK: alembic upgrade head contra PostgreSQL real
detection_job presente: True
columnas: ['id', 'agency_id', 'listing_id', 'photo_id', 'object_key', 'model_id',
           'dedupe_key', 'status', 'attempts', 'lease_expires_at', 'result',
           'failure_reason', 'created_at', 'enqueued_at', 'started_at', 'finished_at']
enqueued_at presente: True
version alembic: 0019_detection_jobs
```

**Qué prueba:** la cadena completa aplica sobre PostgreSQL, la tabla existe con sus 16 columnas —incluida `enqueued_at`, la que la reconciliación necesita— y el head queda en `0019_detection_jobs`. Sin `enqueued_at` en la base, la mitad barata de la reconciliación no funcionaría; acá se ve que está.

**De paso:** esto avanza sobre `GAP-092` (migraciones del Sprint 1 pendientes contra PostgreSQL real), al menos para las migraciones `0017`–`0019`.

## 2. Cola real en Floci

La cola dedicada se creó en el emulador:

```bash
docker compose -f infra/docker/compose.local.yml exec -T floci \
  aws --endpoint-url http://127.0.0.1:4566 sqs create-queue --queue-name roomforge-local-detection
```

```json
{ "QueueUrl": "http://localhost:4566/000000000000/roomforge-local-detection" }
```

## 3. Ida y vuelta por la cola con el código de producción

Publicado con `SqsJobQueue` —la clase que usa la API, no un doble— y recibido con el cliente real:

```
PUBLICADO con SqsJobQueue (codigo de produccion)
RECIBIDO: {"attempt":1,"job_id":"live-job-1","model_id":"ssdlite320-mobilenetv3-coco-v1",
           "object_key":"agencies/a/listings/l/photos/p","photo_id":"live-photo-1","version":1}
IDA Y VUELTA OK: el cuerpo recibido es identico al publicado
```

**Qué prueba:** el mensaje llega a la cola real y vuelve **byte por byte igual** al publicado; el formato compacto con claves ordenadas que documenta `docs/api/f08-detection-jobs.md` es el que efectivamente viaja, y `JobMessage.from_body` lo reconstruye sin pérdida. El contrato del mensaje deja de ser una promesa del documento y pasa a ser un hecho observado.

## 4. Lo que sigue **sin verificar** después de esta corrida

Se declara, no se disimula:

1. **Inferencia real dentro del contenedor del worker.** No se construyó la imagen `Dockerfile.worker` (~1,5 GB con torch) ni se corrió el ciclo completo `claim → descarga firmada desde S3 → inferencia → complete`. La lógica está probada con dobles y el detector está probado por separado en F08.2; **la unión de las dos cosas contra infraestructura real, no**.
2. **Floci no es SQS.** Visibilidad, orden y garantías de entrega pueden diferir. Nada de esto autoriza conclusiones sobre SQS real, que pertenece a F11.
3. **Los valores de reintento, visibilidad y lease siguen siendo elegidos, no medidos.**

## 5. Hallazgos operativos (cuestan tiempo si se redescubren)

1. **Las variables de entorno de WSL no llegan al Python de Windows.** `export DATABASE_URL=...` seguido de `.venv/Scripts/python.exe` deja al proceso sin la variable, y alembic lee una URL vacía del `.ini` y falla con `Could not parse SQLAlchemy URL from given URL string`. La solución es fijarla **dentro del proceso**. Vale para cualquier script de este repositorio que combine shell de WSL con el intérprete de Windows.
2. **`docker.exe` no entiende rutas `/mnt/d/...`.** Las convierte en `D:\mnt\d\...` y falla. Con rutas **relativas** desde la raíz del worktree funciona.
3. **El propio bucle de espera de salud estaba mal.** El patrón `case` esperaba `postgres=healthy` antes que `floci=healthy`, y el orden real es el inverso: esperó 90 segundos de gusto aunque los contenedores ya estaban sanos. Un chequeo de salud que falla en silencio es peor que no tenerlo.
