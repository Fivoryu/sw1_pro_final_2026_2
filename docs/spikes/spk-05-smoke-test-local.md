# SPK-05 — Smoke test del entorno local (Docker Compose + Floci)

| Campo | Valor |
| --- | --- |
| Spike | SPK-05 — Entorno local reproducible con Floci (S3/SQS) |
| Objetivo | Validar que cada integrante levanta el entorno de desarrollo y que Floci cubre las operaciones S3/SQS usadas por RoomForge |
| Responsable | Equipo RoomForge (cada integrante ejecuta el checklist) |
| Estado | En ejecución |
| Fecha inicio | GAP-040: pendiente |
| Fecha cierre | GAP-041: pendiente |

## Alcance

- Docker Compose: frontend, backend FastAPI, PostgreSQL, Floci (S3/SQS) y worker real o simulado.
- SDK AWS (boto3/botocore o el que use el backend) apuntando a Floci solo por configuración (endpoints/credenciales), sin cambiar código.

## Prerrequisitos por integrante

| ítem | Estado |
| --- | --- |
| Git + Docker Desktop (WSL2 o Hyper-V) | GAP-042 |
| Puerto 5432 libre (PostgreSQL) | GAP-043 |
| Espacio en disco (imágenes + volúmenes) | GAP-044 |
| `.env` local según plantilla del repo | GAP-045 |

## Checklist de verificación (una fila por integrante)

| # | Paso | Comando / verificación | Resultado (SÍ / NO / fallo) | Tiempo (min) | Observaciones |
| --- | --- | --- | --- | --- | --- |
| 1 | Levantar stack | `docker compose up -d` | GAP | GAP | GAP |
| 2 | Salud backend | `GET /health` responde 200 | GAP | GAP | GAP |
| 3 | PostgreSQL | Conexión desde el contenedor backend | GAP | GAP | GAP |
| 4 | Floci S3 — crear bucket | CreateBucket | GAP | GAP | GAP |
| 5 | Floci S3 — put/get/list/delete | PutObject, GetObject, ListObjects, DeleteObject | GAP | GAP | GAP |
| 6 | Floci S3 — URL pre-firmada | Generar y consumir Presigned GET y PUT | GAP | GAP | GAP |
| 7 | Floci SQS — crear cola | CreateQueue | GAP | GAP | GAP |
| 8 | Floci SQS — send/receive/delete | SendMessage, ReceiveMessage, DeleteMessage | GAP | GAP | GAP |
| 9 | Floci SQS — visibility timeout | Receive con timeout corto y reprocesamiento | GAP | GAP | GAP |
| 10 | Worker | Worker simulado consume y marca trabajo | GAP | GAP | GAP |
| 11 | Frontend | Panel React carga y habla con la API | GAP | GAP | GAP |

> Regla: las credenciales y endpoints de Floci se inyectan por configuración (`.env`), nunca hardcodeadas. Si algo NO funciona, registrar el fallo completo: comando, error, versión de Docker/floci.

## Conclusiones que alimentan decisiones

| Decisión | Regla propuesta (completar al cerrar el spike) |
| --- | --- |
| Cobertura Floci S3/SQS | GAP-046: operaciones confirmadas operativas |
| URLs pre-firmadas en dev | GAP-047: si Floci no las soporta → subir capturas vía API (proxy) en local |
| Onboarding de integrantes | GAP-048: tiempo promedio del checklist y problemas comunes |
| Estado de CI | GAP-049: si el smoke test corre en CI o solo local |
| Worker simulado | GAP-050: confirmar que el modo simulado desacopla el desarrollo de la GPU |
