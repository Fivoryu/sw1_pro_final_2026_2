# Tasks — Trabajos asíncronos de detección (F08.4)

Cada tarea cierra con su verificación y con un commit de unidad de trabajo. El usuario autorizó commits para esta rama (S11); **no** autorizó push, merge ni PR.

## F08A-T1 — Modelo y migración

- **Specs:** R1 (estados), R2 (unicidad de idempotencia), R7 (campos de lease).
- **Entrega:** módulo `backend/app/modules/detection/` con `models.py` (`DetectionJob`), `schemas.py` y la migración `0019_detection_jobs` que sigue a `0018_listing_photos`.
- **Verificación:** prueba de que los cuatro estados son los únicos admitidos y de que `dedupe_key` es único (segundo insert con la misma clave falla); migración aplicada y revertida contra SQLite en las pruebas, sin afirmar nada sobre PostgreSQL.
- **Commit:** unidad propia.

## F08A-T2 — API que persiste y publica

- **Specs:** R1, R2, R3, R8, R11.
- **Entrega:** `job_queue.py` (`SqsJobQueue`, `InMemoryJobQueue` con fallo a pedido), `service.py` con alta idempotente y publicación **después de confirmar el trabajo**; `enqueued_at` se marca condicionalmente sólo si `attempts` sigue en la misma generación y el trabajo continúa `pending`. Incluye `router.py` de personal, inyección de la cola en `create_app`, ajustes de configuración y `docs/api/f08-detection-jobs.md` con el contrato del mensaje.
- **Verificación:** RED y GREEN de R2 (dos peticiones, un trabajo), R3 (la publicación fallida devuelve error explícito y deja el trabajo `pending` sin marca; la repetición o el barrido vuelve a publicar) y R8 (401/403/404 sin crear trabajo ni publicar mensaje).
- **Commit:** unidad propia.

## F08A-T3 — Consumidor

- **Specs:** R4, R5, R9, R10.
- **Entrega:** `worker3d/job_worker.py` con cola, cliente HTTP y función de inferencia inyectables; endpoints `claim`, `complete` y `fail` con token de servicio fail-closed; `infra/docker/inference/Dockerfile.worker` y `requirements-worker.txt`; servicio del worker en el overlay; cola `roomforge-local-detection` en el script de provisionamiento.
- **Verificación:** RED y GREEN de R4 (el worker reutiliza el módulo de inferencia y guarda clase, puntuación, caja y versión de modelo) y R5 (segundo procesamiento del mismo mensaje no vuelve a inferir ni a informar); el servicio de inferencia queda **sin cambios** y su digest intacto.
- **Commit:** unidad propia.

## F08A-T4 — Reintentos, visibilidad y recuperación

- **Specs:** R6, R7.
- **Entrega:** tope de intentos y motivo en `fail`; barrido de leases vencidos como tarea de fondo, con el patrón del refresher de tasas; ajustes declarados en configuración.
- **Verificación:** RED y GREEN de R6 (fallo permanente termina `failed` tras exactamente el tope, con motivo) y R7 (`running` con lease vencido se republica; con intentos agotados pasa a `failed`).
- **Commit:** unidad propia.

## F08A-T5 — Verificación integrada

- **Specs:** R3 (segunda mitad), R5, R12.
- **Entrega:** prueba del mensaje sin trabajo descartado sin reintento; corrida del conjunto completo del backend; verificación contra Floci real de que la cola recibe y entrega un mensaje.
- **Verificación:** suite del backend en verde, Ruff y Pyright sin diagnósticos nuevos; salida real registrada. Si Floci no está disponible, se declara **no verificado** en vez de simularlo.
- **Commit:** unidad propia.

## F08A-T6 — Trazabilidad

- **Specs:** S8, S12.
- **Entrega:** `docs/plan-maestro-roomforge.md` (§1.4.1 y §F08) y `worker3d/README.md`; registro de ejecución en `odd/tasks/f08-async-jobs.md`; `apply-progress` del cambio.
- **Verificación:** F08 sigue declarada parcial, con F08.5 y F08.6 pendientes y la dependencia de F06 visible.
- **Commit:** unidad propia.

## Fuera de estas tareas

F08.5 (confirmación humana e inventario) y F08.6 (mejora opcional). No se crean sus artefactos ni se declaran ejecutadas. El contrato «sugerencias de IA (F08 ↔ F05/F06)» **no** se congela acá.
