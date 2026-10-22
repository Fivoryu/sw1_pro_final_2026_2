# F07 — Guía para probar la captura en un teléfono y completar la fase

Esta guía permite que otra persona del equipo levante el circuito completo de F07 en su equipo, lo pruebe con un teléfono Android y cierre lo pendiente. El registro de ejecución está en `odd/tasks/f07-spatial-capture.md`; el contrato del paquete, en `docs/api/f07-capture-package.md`.

## Qué hay implementado

| Superficie | Qué hace |
|---|---|
| App de captura (`apps/captura_mobile`) | Sesión ARCore propia en Kotlin; modo por paredes y recorrido continuo con guía (indicaciones, minimapa de cobertura, voz y vibración); cuadros clave con pose y profundidad; «Siguiente ambiente»; paquete ZIP y subida con reintentos sin duplicar. |
| Backend (`backend/app/modules/reconstruction`) | Registro de capturas, subida firmada a S3, cola de reconstrucción, estado, listado y aceptación; barridos de lease y de retención (los cuadros se borran al aceptar o a los 30 días). Migraciones `0024` y `0025`. |
| `worker3d` | Paquete → paredes, contorno, altura, volúmenes por profundidad y escena v2 (`reconstruct.py`, `reconstruction_worker.py`). |
| Panel | «Capturas reconstruidas» en el editor de escena: estado, advertencias, cargar el borrador y aceptarlo al guardar. |

## Requisitos

- Windows con Docker Desktop, el `.venv` de la raíz y Flutter (los comandos de Flutter se ejecutan desde PowerShell).
- **Memoria:** compilar el APK con menos de ~3 GB libres tarda más de 9 minutos; cerrar el navegador ayuda.
- Un teléfono Android **compatible con ARCore** con «Servicios de Google Play para RA» actualizado, conectado por USB con depuración activada.

## 1. Servicios locales

```powershell
# PostgreSQL (puerto 5434) y Floci (S3/SQS en 4566)
docker compose -f infra/docker/compose.postgres.yml up -d
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml up -d floci

# Bucket y colas
.\infra\docker\init-local-resources.ps1
docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml exec -T floci aws --endpoint-url http://127.0.0.1:4566 sqs create-queue --queue-name roomforge-local-reconstruction
```

`init-local-resources.ps1` puede fallar al aplicar la política de reintentos de la cola de **detección** (F08); no afecta a F07, pero conviene corregirlo.

## 2. Base de datos y agente de prueba

Crear una base nueva, migrarla y sembrar agencia, agente e inmueble en borrador. El script escribe la contraseña y el secreto TOTP en un archivo **fuera del repositorio**:

```powershell
cd backend
$env:DATABASE_URL = "postgresql+psycopg://roomforge:<clave>@localhost:5434/roomforge_f07"
..\.venv\Scripts\python.exe -m alembic upgrade head
$env:STAFF_TOTP_ENCRYPTION_KEY = "<la misma clave Fernet que usará la API>"
$env:PYTHONPATH = "."
..\.venv\Scripts\python.exe scripts\seed_local_capture.py $env:TEMP\roomforge-f07-agent.txt
```

Agregar el secreto TOTP del archivo a una app de autenticación («Ingresar clave de configuración»).

## 3. API y worker

Variables mínimas para la API (además de `DATABASE_URL` y `STAFF_TOTP_ENCRYPTION_KEY`):

```text
JWT_SECRET=<32 bytes o más>
STAFF_WEB_ORIGIN=http://localhost:5173
S3_ENDPOINT_URL=http://127.0.0.1:4566
S3_PUBLIC_ENDPOINT_URL=http://127.0.0.1:4566
S3_BUCKET_NAME=roomforge-local-assets
S3_ACCESS_KEY_ID=local-test-key
S3_SECRET_ACCESS_KEY=local-test-secret
SQS_ENDPOINT_URL=http://127.0.0.1:4566
AWS_ACCESS_KEY_ID=local-test-key
AWS_SECRET_ACCESS_KEY=local-test-secret
AWS_DEFAULT_REGION=us-east-1
RECONSTRUCTION_WORKER_TOKEN=<token compartido con el worker>
```

```powershell
# API (desde backend/)
..\.venv\Scripts\python.exe -m uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8007

# Worker (desde la raíz, con las mismas variables más esta)
$env:RECONSTRUCTION_API_BASE_URL = "http://127.0.0.1:8007"
.venv\Scripts\python.exe worker3d\reconstruction_worker.py
```

## 4. App en el teléfono

```powershell
cd apps\captura_mobile
flutter.bat build apk --debug --dart-define=ROOMFORGE_API_BASE_URL=http://127.0.0.1:8007
adb install -r build\app\outputs\flutter-apk\app-debug.apk
adb reverse tcp:8007 tcp:8007   # API
adb reverse tcp:4566 tcp:4566   # Floci: la URL de subida firmada apunta a 127.0.0.1:4566
```

Los túneles se pierden al reiniciar o desconectar el teléfono.

## 5. Prueba

1. Ingresar con el agente sembrado → inmueble «Borrador local…» → «Medir ambientes» → **modo recorrido**, con buena luz.
2. Apuntar al piso hasta que se habilite «Iniciar recorrido»; caminar por el borde del ambiente siguiendo la guía; «Siguiente ambiente» al cruzar una puerta; «Terminar recorrido».
3. En la tarjeta de subida, esperar «Borrador listo» («Actualizar estado»).
4. En el panel: editor de escena → «Capturas reconstruidas» → cargar el borrador → guardar la escena → la captura queda «Aceptada».

Registrar en `odd/tasks/f07-spatial-capture.md`: tamaño del paquete, `droppedKeyframes`, tiempo de reconstrucción, el borrador obtenido y las medidas reales con cinta frente a las de la app (issue #24).

Sin teléfono, la prueba de punta a punta con un paquete sintético está registrada en la bitácora (L21).

## Problema conocido en el Galaxy S23 FE con Android 16

En el S23 FE de pruebas (`SM-S711B`, Android 16, build `BP4A.251205.006`, ARCore 1.57) el seguimiento entra y sale y no se detectan planos ni con piso texturado. ARCore registra miles de `IMU buffer is empty` y `Failed to query IMU integrated pose … timestamp is too new`: los datos de los sensores no le llegan a tiempo. Reiniciar el teléfono, diferir la profundidad y fijar el foco quitaron los cuadros descartados, pero no el problema de los sensores. Hay un reporte abierto muy parecido en un Galaxy A54 con la misma base de Android 16, donde también falla la app de ejemplo oficial de Google: [google-ar/arcore-android-sdk#1784](https://github.com/google-ar/arcore-android-sdk/issues/1784). **No está confirmado** que sea el mismo defecto: para confirmarlo, probar la app de ejemplo «Hello AR» de Google en el mismo teléfono. Mientras tanto, conviene probar con **otro teléfono** compatible.

## Pendiente para cerrar F07

- [ ] Prueba completa en un teléfono donde ARCore detecte planos: orientación de imagen y profundidad frente a la pose, conversión YUV real, máscara DEPTH16, ritmo del grabador y tamaño del paquete.
- [ ] Tolerancias medidas con cinta (issue #24) y escena enviada desde el teléfono.
- [ ] Verificación independiente de los cambios de alto riesgo: migraciones `0024`/`0025` y contrato de escena (`ETag`, procedencia) y de capturas.
- [ ] Decisión de producto: en sesiones de varios ambientes, ¿bloquear la sincronización de la escena armada en el teléfono y dejar solo la reconstrucción del worker?
- [ ] Puertas y ventanas: el worker no las detecta (las marca la agencia en el editor).
- [ ] Rendimiento del worker en Python puro con paquetes reales (sin medir) y del teléfono en gama media de 4 GB (sin medir).
