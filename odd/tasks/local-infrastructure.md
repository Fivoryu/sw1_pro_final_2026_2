# Preparar infraestructura local de RoomForge

## Objetivo y autorización

Crear una configuración nueva de Docker Compose para PostgreSQL y Floci (S3/SQS), documentar su uso y comprobar los servicios con operaciones reales. El usuario autorizó la implementación de infraestructura local; el despliegue AWS queda fuera de alcance.

## Alcance y restricciones

- Crear `infra/docker/compose.local.yml`; no restaurar ni recrear `infra/docker/compose.postgres.yml`.
- La configuración solo ejecutará PostgreSQL y Floci. No restaurar ni inventar backend, panel, worker ni otras aplicaciones.
- Documentar preparación, inicio, conexión, validación y detención en `infra/README.md`.
- Mantener secretos reales fuera del repositorio; por autorización del usuario, la plantilla local será `infra/docker/local-env.example` (nombre sin punto inicial). No crear ni modificar un `.env` real.
- Preservar todos los cambios existentes y volúmenes Docker ajenos. No ejecutar `down -v`, `prune`, ni limpiezas globales.
- No modificar los submódulos backend/panel/cliente, documentación histórica, OpenSpec, `AGENTS.md`, `README.md` raíz o el binario de Enterprise Architect.
- No hacer commit ni push, por instrucción explícita del usuario.
- Cambio de ruta autorizado por el usuario después del bloqueo del escritor: usar `infra/docker/local-env.example` en lugar de `.env.example`; las superficies completas son `infra/docker/compose.local.yml`, `infra/docker/local-env.example` e `infra/README.md`.

## Estado inicial y decisiones

- Rama: `chore/roomforge-reset-01a0d0ec`.
- El estado inicial ya tenía modificaciones en los submódulos móvil/backend/panel, eliminación de `infra/docker/compose.postgres.yml`, documentos sin seguimiento (`docs/redefinicion-roomforge.md`, `odd/tasks/project-reset.md`) y otros cambios OpenSpec/.pi. No atribuirlos a este trabajo.
- Docker Engine 29.8.0 y Compose v5.5.1 responden; no hay contenedores en ejecución.
- Los puertos 5432, 5434, 4566 y 4576 no tenían listener en la comprobación inicial.
- Hay numerosos volúmenes previos, incluidos `infra_postgres_data`, `roomforge_pgdata` y `proyecto_final_postgres_data`. La nueva configuración debe usar un nombre de proyecto/volúmenes distinto; no inspeccionar, montar ni borrar los existentes.
- Usar PostgreSQL 16 (`5434:5432`), compatible con el puerto local documentado en el checkout, y Floci en `4566`; ambos publicados solo en loopback.
- Fijar la imagen de Floci en `2.1.0-compat`: la documentación oficial indica que el sufijo `-compat` incluye AWS CLI/boto3, útil para verificar S3/SQS sin crear una aplicación. Habilitar persistencia en un volumen nuevo.
- La configuración oficial de Floci documenta S3/SQS en `4566`, modo `persistent` y directorio de datos configurable. No implica paridad total con AWS.
- TDD: no aplica a esta tarea declarativa de infraestructura/documentación; las comprobaciones autoritativas son validación de Compose y smoke tests de conexión/API.

## Tareas

- [x] **INF-01 — Comprobar el estado y fijar límites de preservación.** Revisados git status/rama, disponibilidad de Docker, contenedores, puertos, volúmenes existentes, instrucciones del reinicio y redefinición, y referencias oficiales actuales de Floci. No se modificó ni restauró configuración existente.
- [x] **INF-02 — Crear Compose local y documentar el flujo.** Implementados `infra/docker/compose.local.yml`, `infra/docker/local-env.example` e `infra/README.md`. La configuración declara PostgreSQL y Floci con volúmenes dedicados, loopback y variables oficiales de persistencia de Floci; Compose fue validado y mostró exactamente `floci` y `postgres`. No se iniciaron servicios.
- [x] **INF-03 — Verificar la infraestructura en ejecución.** Compose inició `floci` y `postgres` y ambos quedaron `healthy`; se crearon los volúmenes nuevos `roomforge-local-dev_postgres_data` y `roomforge-local-dev_floci_data`. `pg_isready` y `SELECT current_database(), current_user, 1` confirmaron `roomforge_local`. En Floci se creó y listó `roomforge-local-smoke-20260924`; SQS creó la cola del mismo nombre, envió un mensaje y recibió exactamente `INF-03-smoke-20260924-233347Z-exact-match`. Se intentó eliminar solo ese bucket y esa cola; no se hizo consulta posterior que confirme su ausencia. El stack y sus volúmenes quedaron en ejecución/conservados.

## Criterios de aceptación

1. `docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml config --quiet` acepta la configuración y la plantilla local de variables.
2. El Compose contiene exactamente PostgreSQL y Floci, no monta el socket de Docker, no compila ni inventa aplicaciones y no hace referencia operativa al Compose eliminado.
3. PostgreSQL queda accesible en `127.0.0.1:5434`; Floci responde en `127.0.0.1:4566`; ambos usan volúmenes nuevos y nombrados.
4. La documentación en español permite iniciar/detener el entorno usando `local-env.example`, comprobar PostgreSQL, crear un bucket y enviar/recibir un mensaje SQS. Advierte que Floci es emulación local, no despliegue ni equivalencia completa con AWS.
5. Hay evidencia observada de conexión a PostgreSQL, creación/listado de bucket S3 y envío/recepción SQS; cualquier fallo o limitación se registra sin declarar PASS.
6. `infra/docker/compose.postgres.yml`, los submódulos y todos los cambios preexistentes siguen intactos respecto de su estado inicial.
7. No hay commit ni push.

## Ruta y evidencia de entrega

- **INF-01:** exploración del padre y mapeo read-only delegado por el disparador de 4+ archivos; Docker responde, puertos libres, contenedores vacíos y volúmenes existentes documentados.
- **INF-02:** escritura delegada a `gentle-ai-worker` por tres archivos no triviales; rutas autorizadas por el usuario. Verificación del escritor: `docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml config --quiet` pasó sin salida; `config --services` devolvió solo `floci` y `postgres`. No se ejecutaron contenedores en esta tarea.
- **INF-03:** `gentle_review assess` devolvió `unassessable` por archivos sin seguimiento y prescribió autoverificación más verificación independiente. `gentle-ai-verify` ejecutó los smoke tests: ambos servicios healthy, query PostgreSQL correcta, bucket S3 creado/listado, mensaje SQS enviado/recibido con cuerpo exacto. El padre repitió la consulta SQL como spot-check y obtuvo la misma base/usuario/valor. Los servicios y volúmenes propios quedaron vivos; no se limpiaron volúmenes ni trabajo ajeno.
- Commits: ninguno, prohibidos explícitamente por el usuario.

## Progreso y siguiente paso

Las tres tareas están completas. Tras el bloqueo inicial de `.env.example`, el usuario autorizó la plantilla `infra/docker/local-env.example`. Compose pasó `config --quiet` y contiene solo `floci` y `postgres`. La verificación independiente confirmó ambos servicios healthy, conexión/consulta PostgreSQL, creación/listado de bucket S3 y envío/recepción SQS con cuerpo coincidente; el padre repitió la consulta SQL. Se intentó borrar únicamente los recursos de smoke test, pero no se comprobó después su ausencia. El stack y sus volúmenes nuevos permanecen en ejecución/conservados. No se tocó el backend/panel, no se recreó el Compose eliminado y no hubo commit ni push.

## Fuentes técnicas

- Floci Quick Start: <https://floci.io/floci/getting-started/quick-start/>.
- Floci configuración e imagen/versiones: <https://github.com/floci-io/floci/blob/main/README.md>.
- Referencia oficial SQS: <https://github.com/floci-io/floci/blob/main/docs/services/sqs.md>.
- Release consultado: <https://github.com/floci-io/floci/releases/tag/2.1.0>.
