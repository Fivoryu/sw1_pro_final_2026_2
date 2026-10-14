# F08.4 — Trabajos asíncronos de detección (API + cola + worker)

Este documento es la especificación que leen los subagentes: leer hasta `## Log`.
Subfase F08.4 del `docs/plan-maestro-roomforge.md`. Rama `feat/f08-furniture-ai-pilot`, worktree `proyecto_final-f08-ai-wt`. Registro SDD en `openspec/changes/f08-trabajos-asincronos/`.
Unidad **grande y de riesgo alto** (concurrencia): exige verificación independiente al cerrar.

## Specs

S1. Acciones de F08.4 (§F08): «API persiste trabajo, publica mensaje, worker descarga imagen autorizada y guarda resultado. Recuperar fallo entre persistir/encolar; limitar reintentos, visibilidad y trabajos fallidos. SQS puede entregar duplicados.»

S2. Salida de F08.4 (§F08): «estados pendientes/en curso/completados/fallidos y reintento controlado.»

S3. Aceptación de F08.4 (§F08): «duplicar mensaje no duplica inventario; reiniciar worker permite recuperación. Esta subfase se adapta si se elige móvil, no se impone nube por defecto.»

S4. La modalidad elegida en F08.3 es **worker en PC/servidor** (`docs/ai/f08-decision-empaquetado.md`), así que F08.4 **aplica** y no se adapta: la cola de mensajes es el camino previsto.

S5. Contrato primero (§1.5 regla 6): «Cuando dos fases comparten una interfaz, esa interfaz se congela y se documenta antes de que cada rama implemente... Interfaces conocidas: ... **sugerencias de IA (F08 ↔ F05/F06)**». Ese contrato **sigue sin congelarse** (el borrador de `objects[]` de F06 no tiene campos de sugerencia). Consecuencia vinculante: **F08.4 no escribe en el inventario comercial** (`ListingExtra` de F05.1) ni en la escena de F06. Persiste **sugerencias**, que es lo que F08.5 confirmará después.

S6. Interpretación de S3 registrada, no silenciada: la frase «duplicar mensaje no duplica inventario» se cumple en esta unidad como **«duplicar mensaje no duplica el trabajo ni su resultado persistido»**, porque la ruta a inventario confirmado pertenece a F08.5 y su contrato no existe (S5). Se cita literal y se declara la interpretación.

S7. Migraciones (§1.5 regla 7): «Si dos ramas agregan migraciones, la segunda rebasa.» El head actual es `0018_listing_photos`; esta rama no agrega ninguna hasta ahora.

S8. Flujo SDD obligatorio (§5.4): «Antes de código sustancial, resolver requisitos y seguir el flujo SDD del proyecto».

S9. Reintentos y visibilidad (§F08.4, S1): los reintentos son **acotados**, los fallidos **quedan registrados como fallidos** (no se pierden en silencio) y la recuperación ante reinicio es **verificable**.

S10. Cola local: el stack local ya provee SQS vía Floci (`infra/docker/compose.local.yml`, servicio `floci`, `SQS_QUEUE_NAME=roomforge-local-events`). **Verificado: el backend no tiene hoy ningún código de cola, outbox ni publicación.** Esta unidad introduce el primer productor y el primer consumidor del proyecto. Nada de esto autoriza AWS real (F11).

S11. Commits (AGENTS.md regla dura 1, con autorización del usuario): el usuario autorizó commits («Autorizo los commits», 2026-10-14) mientras se trabajaba esta fase. Se toma como autorización **vigente para las unidades de trabajo de esta rama**; **no cubre push, merge ni PR**. Si el usuario la revoca, se dice y los commits quedan pendientes.

S12. Evidencia (AGENTS.md regla dura 4): «No silenciar GAPs ni inventar evidencia.» Un valor no observado se registra como **no medido**.

## Tasks

- **F08A-T1 — Modelo y migración** (S1, S2, S7). Tabla de trabajos de detección con estado (`pending`/`running`/`completed`/`failed`), clave de idempotencia, intentos, marca de error y resultado. Superficie `backend/app/modules/`, `backend/alembic/versions/`, `backend/tests/`. Commit por unidad.
- **F08A-T2 — API que persiste y publica** (S1, S5, S10). Endpoint de personal que crea el trabajo de una foto, publica el mensaje en SQS y **recupera el fallo entre persistir y encolar**. Sin escribir inventario. Superficie `backend/app/modules/`, `backend/tests/`, `docs/api/`. Commit por unidad.
- **F08A-T3 — Consumidor** (S1, S9). Worker que toma el mensaje, verifica el trabajo, descarga la imagen autorizada desde S3, ejecuta el detector existente y guarda el resultado. Superficie `worker3d/`, `infra/docker/`, `worker3d/tests/`. Commit por unidad.
- **F08A-T4 — Reintentos, visibilidad y recuperación** (S1, S9). Reintentos acotados, visibilidad declarada, marca de fallido con motivo, y recuperación de trabajos que quedaron en curso tras un reinicio. Superficie `worker3d/`, `backend/app/modules/`, `backend/tests/`. Commit por unidad.
- **F08A-T5 — Verificación integrada** (S3, S6). Duplicado de mensaje que **no** duplica trabajo ni resultado; reinicio del worker que recupera; conjunto de pruebas en verde. Commit por unidad.
- **F08A-T6 — Trazabilidad** (S8, S12). Plan maestro §1.4.1 y §F08, `worker3d/README.md`, este registro. Commit por unidad.

## Log

L1 (usuario, verbatim): «Haz 8.4»

L2 (alcance decidido por el orquestador, 2026-10-14): se implementa F08.4 completo —persistencia, publicación, consumidor, reintentos y recuperación— porque S4 confirma que la modalidad elegida es servidor. F08.5 y F08.6 quedan fuera, y F08.5 sigue bloqueada por F06.

L3 (verificación previa, 2026-10-14): el backend tiene los módulos `agencies`, `catalog`, `customer_identity`, `exchange_rates`, `health`, `identity` y `reservations`; `boto3` ya es dependencia; el head de Alembic es `0018_listing_photos`. **No hay ninguna referencia a SQS en el código**: sólo variables de entorno en el Compose. El mapa detallado de los patrones del backend (modelo de fotos, claves S3, DI, idempotencia de reservas, dobles de AWS en pruebas) se delegó a `gentle-ai-explore` y se registra en el artefacto `explore` del cambio SDD antes de diseñar.

L4 (hallazgo real durante T2, 2026-10-14): la primera implementación de la ventana persistir/encolar **no funcionaba**, y la prueba lo demostró.

El trabajo sobrevivía a una publicación fallida. La causa raíz: el código envolvía el `INSERT` en `session.begin_nested()` para sobrevivir a una carrera sobre la clave de deduplicación, y con el driver `pysqlite` **liberar el `SAVEPOINT` más externo confirma la transacción**. O sea, el savepoint commiteaba antes de tiempo y el rollback posterior no tenía nada que deshacer. El rollback sí ocurría; el dato ya estaba confirmado.

Se probaron hipótesis y se descartaron con evidencia: no era autocommit (`app/db/session.py` instala un **autorizador SQL**, no cambia el modo de transacción) y no era el manejador de errores (el `503` con `dependency_unavailable` es un saneador global de cuerpos `5xx`, así que el detalle interno no llega al cliente).

**Decisión:** una base y una cola no se confirman juntas, así que el diseño dejó de aparentarlo. Ahora el trabajo se inserta, se publica y `enqueued_at` se fija **sólo si la publicación tuvo éxito**; si falla, el trabajo queda `pending` sin encolar y el mismo pedido repetido —o el barrido— lo republica. La carrera se resuelve **sin savepoint**: la restricción única rechaza el segundo `INSERT` y la petición relee al ganador en una transacción nueva y responde `200`. `session.begin_nested()` queda prohibido en el módulo, con la razón escrita en `service.py` y en el `design` del cambio SDD.

**Consecuencia secundaria descubierta:** el proyecto sanea los cuerpos `5xx` (un `503` devuelve `dependency_unavailable`, no el detalle interno). El contrato con el cliente es el código de estado, y el `job_id` se obtiene por `GET /detections`. Queda documentado en `docs/api/f08-detection-jobs.md`.

**Y un error propio que corregí en el acto:** en una edición dejé un marcador sin sentido (`_UnusedFixtureSentinel` y un `test_X` que lanzaba `NotImplementedError`) en el archivo de pruebas. Los tests lo habrían detectado, pero lo encontré yo al releer el archivo antes de correrlo. Mismo patrón que antes: **leer el artefacto**, no confiar en haberlo escrito.

L5 (verificación contra infraestructura real, 2026-10-14): se ejecutó contra PostgreSQL y Floci locales, no con dobles. Evidencia completa con comandos y salidas en `docs/ai/f08-async-jobs-verificacion.md`.

- **Migración `0019` aplicada a PostgreSQL real** (antes sólo se había probado contra SQLite, que era un hueco de verdad): la cadena `0017 → 0018 → 0019` corre entera, `detection_job` existe con sus 16 columnas —incluida `enqueued_at`— y el head queda en `0019_detection_jobs`. Avanza parcialmente sobre `GAP-092`.
- **Cola real creada en Floci** y **ida y vuelta con el código de producción**: publicado con `SqsJobQueue` y recibido con el cliente real, el cuerpo vuelve **byte por byte igual**. El contrato del mensaje deja de ser una promesa del documento.
- **Sigue sin verificarse:** la inferencia real dentro del contenedor del worker (no se construyó la imagen de ~1,5 GB con torch, así que el ciclo completo `claim → descarga firmada → inferencia → complete` no se ejecutó contra infraestructura real aunque sí con dobles), el comportamiento de SQS real frente a Floci, y los valores de reintento/visibilidad/lease que siguen siendo elegidos y no medidos.
- **Tres hallazgos operativos que cuestan tiempo si se redescubren:** las variables de entorno de WSL **no llegan** al Python de Windows (hay que fijarlas dentro del proceso); `docker.exe` no entiende rutas `/mnt/d/...` (usar relativas); y mi propio bucle de espera de salud tenía el orden del patrón invertido y esperó 90 segundos de gusto con los contenedores ya sanos.

L6 (incidente del escritor, 2026-10-14): el subagente que implementaba T4 murió por **timeout** tras reportar un error. Diagnostiqué antes de reintentar: había dejado 217 líneas sanas, los archivos prohibidos intactos y las pruebas funcionando. La única falla era **una prueba inestable** —contaba iteraciones dentro de una ventana fija de 0,06 s mientras cada barrido corre en un hilo—, no un defecto del código. La arreglé para que espere la condición con un tope y agregué un guardián al comando de commit: **sin suite verde, no se commitea**. La primera vez el guardián se negó correctamente, porque el log todavía no tenía el resumen. Lección: un timeout de un subagente no se reintenta a ciegas; primero se diagnostica qué dejó.
