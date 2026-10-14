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

## 1.1 Migración `0020` contra PostgreSQL real — evidencia del padre

El padre de esta tarea informa que aplicó `0020_detection_job_claim_token` a un PostgreSQL real. Según su evidencia, la columna `claim_token` quedó presente en `detection_job` y el head de Alembic quedó en `0020_detection_job_claim_token`.

**Atribución:** este dato se registra a partir de la evidencia aportada por el padre; no se volvió a ejecutar ni a inspeccionar PostgreSQL real durante el cierre de estos hallazgos.

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

## 6. Cierre de los cinco hallazgos de la tercera verificación

- **G1:** el consumidor lee `ApproximateReceiveCount`; ante un claim no-404 sin token conserva la entrega hasta superar `DETECTION_MAX_ATTEMPTS`, luego registra el error y la elimina. El trabajo no cambia desde el worker; la prueba integrada deja un trabajo pendiente y sin marca, y el barrido lo vuelve a publicar. El provisionamiento configura `roomforge-local-detection-dlq` como destino de redrive.
- **G2:** los endpoints remotos requieren `S3_ACCESS_KEY_ID` y `S3_SECRET_ACCESS_KEY` explícitos antes de crear clientes boto3; el almacenamiento local sigue usando placeholders.
- **G3:** `complete` y `fail` devuelven `409` para un token con un surrogate aislado, sin cambiar el trabajo.
- **G4:** tras una actualización de marca con cero filas se relee el trabajo; una marca concurrente de la misma generación y aún pendiente cuenta como éxito.
- **G5:** se actualizaron el contrato API, el diseño/tareas SDD y el README del worker. La evidencia de PostgreSQL para `0020` se atribuye al padre en §1.1.

**Validación observada en el worktree:** desde `backend/`, `python.exe -m pytest tests -q` → `711 passed, 3 skipped`; `python.exe -m ruff check app tests` → limpio; `pyright.exe app tests` → 18 errores preexistentes de imports `eth_account`/`eth_utils`, sin diagnósticos en los archivos de esta unidad. Desde la raíz, `python.exe -m pytest worker3d/tests -q` → `44 passed`. La prueba de provisionamiento ejecutó el script PowerShell con un Docker simulado y comprobó el `RedrivePolicy` (dead-letter ARN y `maxReceiveCount=4`); el parser de Windows PowerShell también informó `PowerShell syntax OK`.

**No ejecutado en este cierre:** el script de provisionamiento contra Docker/Floci, el redrive real de Floci/SQS ni PostgreSQL. La migración `0020` y su columna `claim_token` se registran únicamente según evidencia aportada por el padre; ver §1.1.

## 7. Cierre de los hallazgos de la cuarta verificación

### H1 — Sweep definitivo para `pending`

El barrido ahora selecciona `pending` con `enqueued_at IS NULL` **o** con una marca de al menos `DETECTION_LEASE_SECONDS` (300 s por defecto). La API pasa el valor configurado al barrido. Cinco minutos superan el intervalo de sweep de 60 s y dan tiempo a una entrega sana para ser reclamada; una marca reciente no se vuelve a publicar en cada vuelta. Antes de publicar una marca antigua, el barrido la limpia; si la publicación falla, el trabajo sigue seleccionable. Tras publicar, la marca se vuelve a fijar. Así, la ruta worker capped-drop puede borrar una entrega conservando su marca vieja, pero no puede dejar el trabajo `pending` invisible para siempre.

**RED observado antes de implementar H1:**

```text
cd backend && /mnt/d/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final/.venv/Scripts/python.exe -B -m pytest -p no:cacheprovider tests/test_detection_recovery.py -q -k 'claim_failures_beyond_receive_cap or pending_job_with_stale_enqueue_marker or recent_enqueue_marker or running_job_with_active_lease or pending_job_that_was_never_enqueued'
2 failed, 3 passed, 6 deselected, 1 warning in 2.38s
```

Fallaron `test_claim_failures_beyond_receive_cap_drop_delivery_and_recover_job` y `test_pending_job_with_stale_enqueue_marker_is_republished`: ambos observaron `recovered == 0` donde se esperaba `1`. El primero ahora siembra explícitamente `pending` **con** `enqueued_at` de hace 10 minutos, confirma que el worker capped-drop deja esa marca, y verifica el republicado. Los casos de marca nula, marca reciente y lease activo cubren los límites alternos.

**GREEN observado:** el mismo comando → `5 passed, 6 deselected, 1 warning in 4.69s`.

### H2 — DLQ y worker comparten el tope

`init-local-resources.ps1` ahora lee `DETECTION_MAX_ATTEMPTS`, valida que sea un entero positivo y configura `maxReceiveCount` con una recepción adicional; sin override, el default 3 coincide con la configuración de la API y el worker. La prueba inyecta 7 y exige un `maxReceiveCount` de 8.

**RED observado:**

```text
cd backend && /mnt/d/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final/.venv/Scripts/python.exe -B -m pytest -p no:cacheprovider tests/test_detection_local_provisioning.py -q
1 failed in 1.14s
```

Fallo observado: `maxReceiveCount` real `4`, esperado `8` con `DETECTION_MAX_ATTEMPTS=7`.

**GREEN observado:** el mismo comando → `1 passed in 1.04s`.

### H3 — Un claim concurrente no es un fallo de cola

Si la actualización de `enqueued_at` afecta cero filas, la relectura ahora acepta `running` con la misma generación (`attempts`) como prueba de que el worker ya reclamó el mensaje. Conserva el caso existente de `pending` con la marca de la misma generación. El test hace que la cola reclame de verdad por el endpoint de la API antes de que el publicador fije la marca.

**RED observado:**

```text
cd backend && /mnt/d/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final/.venv/Scripts/python.exe -B -m pytest -p no:cacheprovider tests/test_detection_jobs_api.py -q -k publisher_accepts_a_same_generation_job_claimed_during_publish
1 failed, 16 deselected, 1 warning in 2.17s
```

La respuesta observada era `503` (`dependency_unavailable`) en vez del `201` esperado, pese a que el endpoint de claim había dejado el trabajo `running` en la misma generación.

**GREEN observado:** el mismo comando → `1 passed, 16 deselected, 1 warning in 4.60s`.

### Validación final del cierre

```text
cd backend && /mnt/d/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final/.venv/Scripts/python.exe -B -m pytest -p no:cacheprovider tests/test_detection_*.py -q
54 passed, 1 warning in 20.13s

cd /mnt/d/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final-f08-ai-wt/backend && /mnt/d/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final/.venv/Scripts/python.exe -B -m pytest -p no:cacheprovider tests -q
715 passed, 3 skipped, 4 warnings in 68.75s

cd /mnt/d/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final-f08-ai-wt && /mnt/d/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final/.venv/Scripts/python.exe -B -m pytest -p no:cacheprovider worker3d/tests -q
44 passed in 2.45s

cd /mnt/d/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final-f08-ai-wt/backend && /mnt/d/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final/.venv/Scripts/python.exe -B -m ruff check app tests
All checks passed!
```

```text
cd /mnt/d/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final-f08-ai-wt/backend && /mnt/d/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final/.venv/Scripts/pyright.exe app tests
18 errors, 0 warnings, 0 informations
```

Los 18 errores son los imports preexistentes `eth_account`/`eth_utils`; la salida no incluye ninguno de los archivos modificados. No se ejecutaron provisionamiento real contra Floci, redrive real, PostgreSQL, imagen/inferencia de worker ni SQS de AWS; esos efectos externos siguen sin verificar en este cierre.
