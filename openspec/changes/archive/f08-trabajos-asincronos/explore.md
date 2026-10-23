# Explore — Trabajos asíncronos de detección (F08.4)

- **Cambio:** `f08-trabajos-asincronos`
- **Fase del plan:** F08.4 (`docs/plan-maestro-roomforge.md` §F08)
- **Rama:** `feat/f08-furniture-ai-pilot` · **Worktree:** `proyecto_final-f08-ai-wt`
- **Almacén:** híbrido (OpenSpec + Engram) · **Ejecución:** interactiva
- **Estado de evidencia:** exploración. Nada de infraestructura AWS real, nada de push.

## 1. Qué existe hoy, verificado por el orquestador (2026-10-14)

| Superficie | Estado real |
|---|---|
| Módulos del backend | `agencies`, `catalog`, `customer_identity`, `exchange_rates`, `health`, `identity`, `reservations`. **No hay módulo de detección ni de IA.** |
| Cola de mensajes en el backend | **Ninguna cola de trabajos.** No hay `sqs`/`SQS` ni productor o consumidor de cola en `backend/app/`. |
| Outbox en el backend | **Sí existe, pero para otra cosa**: el correo de desarrollo escribe a un buzón en disco (`backend/app/core/dev_email.py`) y la publicación de inmuebles tiene su propio camino en `catalog/router.py`. Son mecanismos de mensajería con nombre propio, **no** una cola de trabajos. *(Corrección: una versión previa de este documento afirmaba que no existía ningún código de outbox; el mapa delegado lo refutó. Se corrige en lugar de dejarlo pasar.)* |
| Dependencias | `boto3>=1.34` ya está declarado en `backend/pyproject.toml`. |
| Migraciones | Head actual `0018_listing_photos`. Esta rama no agregó ninguna todavía. |
| F08.1–F08.3 | Cerradas en esta misma rama: ficha de candidato, servicio de inferencia en `infra/docker` (sólo CPU), CLI `worker3d/detect.py` con 35 pruebas y piloto medido sobre 24 fotos CC0. El detector **ya funciona**; lo que falta es ejecutarlo por encolado. |
| Fotos de inmueble (F04) | `ListingPhoto` → tabla `listing_photo`, con `object_key` (`String(255)`) como clave de objeto. Las claves se arman como `agencies/{agency}/listings/{listing}/photos/{photo}`. La lectura se resuelve con enlace firmado (`storage.presign_download`), no con URL pública. Rutas de personal bajo `/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/photos`. |
| Anatomía de módulo | `router.py`, `schemas.py`, `service.py`, `models.py`, más archivos satélite cuando hacen falta (`photo_router.py`, `photos.py`, `photo_storage.py`). **No hay `repository.py`**: los servicios usan la sesión ORM directamente. Los routers se registran en `app/main.py`. |
| Persistencia | `DeclarativeBase` compartida; los identificadores son UUID en `String(36)` con `uuid4()`. Las escrituras usan `session_factory.begin()`, que confirma al salir bien y revierte ante excepción. `create_app` acepta `session_factory` y `photo_storage` inyectables y los guarda en `app.state`. |
| Idempotencia existente | Reservas exige cabecera `Idempotency-Key`, guarda la huella del pedido y respalda la unicidad con una restricción en base; un pedido repetido se reproduce y uno cambiado devuelve conflicto. **Es el patrón a imitar.** |
| Cola local ya provisionada | `infra/docker/init-local-resources.ps1` **ya crea la cola** con la CLI de AWS y `infra/README.md` lo documenta. O sea: la cola existe en el stack local; falta el código que la use. |
| Pruebas | Dobles en el código de producción (`InMemoryPhotoStorage`), base SQLite en memoria con `StaticPool`, `create_app` con fábrica y almacenamiento inyectados, y sustitución de la autenticación de personal. **No hay `conftest.py`**: los fixtures viven en cada archivo `test_*.py`. |
| F08.5 y F08.6 | Fuera de alcance. F08.5 sigue **bloqueada por F06**. |

## 2. Restricciones que condicionan el alcance

1. **El contrato compartido no está congelado.** §1.5 regla 6 exige congelar «sugerencias de IA (F08 ↔ F05/F06)» antes de que cada rama implemente, y el borrador de `objects[]` de F06 no tiene campos de sugerencia. Por lo tanto F08.4 **persiste sugerencias y no escribe inventario comercial** (`ListingExtra`) ni la escena de F06.
2. **La aceptación del plan menciona «inventario».** Su lectura literal apuntaría a F08.5, que no existe. La interpretación —«duplicar mensaje no duplica el trabajo ni su resultado persistido»— queda registrada en la especificación como interpretación declarada, con la cita textual al lado.
3. **Riesgo de concurrencia real, no teórico.** El propio plan lo dice: «SQS puede entregar duplicados». A eso se suman la ventana entre persistir y encolar, la visibilidad del mensaje durante el procesamiento y el reinicio del worker con trabajos en curso. Los cuatro son condiciones que hay que diseñar y verificar, no suponer.
4. **Solo local.** Floci emula SQS y S3. Nada de esto autoriza AWS real: F11 sigue pendiente y sus límites no cambian.
5. **El worker no corre en Compose hoy.** El servicio de inferencia actual es de una sola ejecución (`docker compose run --rm`). F08.4 necesita un proceso que escuche; eso agrega un servicio, no cambia el existente.

## 3. Preguntas abiertas y quién las decide

| # | Pregunta | Quién decide | Cuándo |
|---|---|---|---|
| P1 | ¿Quién dispara la detección: una llamada explícita del personal, o automáticamente al subir la foto? | Dueño del producto | Antes de F08.5 |
| P2 | ¿Qué forma tiene el resultado persistido (lista de detecciones con clase, puntuación y caja)? | Diseño, con el contrato pendiente de S5 | En el `design` de este cambio |
| P3 | ¿Cuántos reintentos y qué visibilidad? | Diseño, con valores declarados y verificables | En el `design` |
| P4 | ¿Se borran los resultados al borrar la foto o el inmueble? | Dueño del producto | Antes de F08.5 |

La P1 **no bloquea**: la unidad implementa el disparador explícito —un endpoint que encola un trabajo para una foto, idempotente por foto y versión de modelo— y cualquier disparador automático futuro llama al mismo endpoint. Se registra como decisión de alcance, no como supuesto.

## 4. Hipótesis a validar, no afirmaciones

- Que la ventana entre persistir y encolar se puede cerrar con un estado inicial y una reconciliación, sin necesitar un outbox transaccional completo. **A validar en el diseño.**
- Que el detector existente se puede reutilizar sin cambios desde un proceso consumidor. **A validar en la implementación.**
- Que un doble de SQS en pruebas alcanza para demostrar idempotencia. Si no alcanza, hay que decirlo y correr contra Floci real.
