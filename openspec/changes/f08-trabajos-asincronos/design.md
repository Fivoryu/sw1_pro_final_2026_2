# Design — Trabajos asíncronos de detección (F08.4)

## 1. Decisión central: un solo escritor del estado

El estado del trabajo lo escribe **sólo la API**. El worker no toca la base: pide, informa y termina por HTTP.

**Por qué.** Todo el riesgo de esta unidad es de concurrencia: duplicados de cola, ventana entre persistir y encolar, visibilidad del mensaje, reinicio con trabajos en curso. Si el worker y la API escribieran la misma tabla, cada defensa habría que duplicarla y mantenerla sincronizada, y las dos podrían pisarse. Con un único escritor, la máquina de estados tiene un solo lugar donde es válida y donde se prueba.

**Costo aceptado:** hay que autenticar al worker (ver §8) y el worker necesita un cliente HTTP. A cambio, el worker no recibe credenciales de base, no depende del esquema y la separación sirve tal cual para F11.

## 2. Modelo de datos: `detection_job`

| Columna | Tipo | Rol |
|---|---|---|
| `id` | `String(36)` UUID, PK | Identificador del trabajo |
| `agency_id` | `String(36)` | Autorización: a qué agencia pertenece |
| `listing_id` | `String(36)` | Inmueble |
| `photo_id` | `String(36)` | Foto sobre la que se infiere |
| `object_key` | `String(255)` | Clave del objeto en S3, copiada del `ListingPhoto` al crear el trabajo, para que el worker no consulte el catálogo |
| `model_id` | `String(64)` | Versión lógica del modelo, parte de la clave de idempotencia |
| `dedupe_key` | `String(160)` **único** | `f"{photo_id}:{model_id}"`: es la restricción que hace imposible el trabajo duplicado |
| `status` | `String(16)` | `pending` \| `running` \| `completed` \| `failed` |
| `attempts` | `Integer` | Intentos consumidos |
| `lease_expires_at` | `DateTime(tz)` nullable | Hasta cuándo vale la toma del trabajo |
| `result` | `JSON` nullable | Detecciones y versión de modelo efectivamente usada |
| `failure_reason` | `String(255)` nullable | Motivo legible del fallo |
| `created_at` / `enqueued_at` / `started_at` / `finished_at` | `DateTime(tz)` | Trazabilidad de tiempos. `enqueued_at` vacío significa «persistido pero todavía no encolado»: es la señal que usa la reconciliación |

**Índices:** `dedupe_key` único, más `(status, lease_expires_at)` para el barrido de recuperación y `(listing_id)` para las consultas de personal.

**Sin borrado en cascada.** Si se borra la foto, el trabajo queda; la política de retención es P4, del dueño del producto y sin decidir. Se declara en vez de inventarla.

## 3. Máquina de estados

```
                 crear (idempotente)
                       │
                       ▼
                   pending ────────────────┐
                       │ claim             │ (barrido: lease vencido y attempts < tope)
                       ▼                   │
                   running ────────────────┘
                    │      │
        complete    │      │ fail
                    ▼      ▼
              completed   attempts < tope ? → pending + republicar
                          attempts = tope ? → failed (motivo)

  barrido: running con lease vencido y attempts = tope → failed (motivo: sin confirmación)
```

**Transiciones permitidas, y ninguna otra:** `pending→running`, `running→completed`, `running→pending`, `running→failed`. Un `complete` sobre un trabajo ya `completed` **no** cambia nada y devuelve el resultado guardado (R5).

## 4. Contrato del mensaje

```json
{
  "version": 1,
  "job_id": "<uuid>",
  "photo_id": "<uuid>",
  "object_key": "agencies/<agency>/listings/<listing>/photos/<photo>",
  "model_id": "ssdlite320-mobilenetv3-coco-v1",
  "attempt": 1
}
```

- **Idempotencia:** la clave es `job_id`. El worker **relee el estado antes de trabajar**: si ya está `completed`, no vuelve a inferir y no vuelve a informar.
- El mensaje es autosuficiente: el worker no necesita consultar el catálogo.
- `version` permite cambiar el formato sin romper consumidores viejos.

## 5. La cola, detrás de una interfaz

`job_queue.py` define el contrato y dos implementaciones, siguiendo el precedente de `photo_storage.py` (doble en el código de producción):

| Implementación | Uso |
|---|---|
| `SqsJobQueue` | boto3 contra el endpoint local de Floci; nombre de cola desde configuración |
| `InMemoryJobQueue` | Pruebas; sabe **fallar a pedido** para poder probar R3 |

Se inyecta en `create_app`, igual que `session_factory` y `photo_storage`. **Consecuencia buscada:** todo el backend se prueba sin AWS y sin red.

## 6. La ventana entre persistir y encolar

**Corrección de diseño (2026-10-14, durante T2).** La primera versión de este diseño decía «la publicación va dentro del bloque transaccional: si falla, se revierte todo». **Eso no funcionaba y se cambió.** Lo que pasó, registrado en lugar de borrado:

La prueba de R3 demostró que el trabajo **sobrevivía** a la publicación fallida. La causa raíz resultó ser real y no obvia: el primer código envolvía el `INSERT` en `session.begin_nested()`, y con el driver `pysqlite` **liberar el `SAVEPOINT` más externo confirma la transacción**. O sea: el savepoint que puse para proteger una carrera commiteaba antes de tiempo, y el rollback posterior ya no tenía nada que deshacer. El rollback por excepción sí ocurría; el dato ya estaba confirmado.

Lección que se conserva: **una base y una cola no se confirman juntas.** Cualquier diseño que lo aparente o miente o confirma antes de tiempo.

**Lo que hace el código ahora**, en tres pasos honestos:

1. El trabajo se inserta con `enqueued_at` sin fijar.
2. Se publica el mensaje.
3. `enqueued_at` se fija **sólo si la publicación tuvo éxito**.

Consecuencias, las dos cubiertas:

- **La publicación falla.** El trabajo queda confirmado como `pending` con `enqueued_at` vacío, la petición devuelve `503` y el **reintento de la misma petición vuelve a publicar ese mismo trabajo** (misma clave de deduplicación, devuelve `200`). Ésa es la mitad barata de la reconciliación; el barrido de §7 es la otra. Sin esto, un trabajo quedaría esperando para siempre a un mensaje que nadie envió.
- **Se pierde la carrera contra otra petición idéntica.** La restricción única de `dedupe_key` rechaza el segundo `INSERT` al confirmar. No se usa savepoint: la petición captura el conflicto, **vuelve a leer el trabajo ganador en una transacción nueva** y lo devuelve como repetición (`200`). `session.begin_nested()` queda prohibido en este módulo, y la razón está escrita en el propio `service.py`.

**Mensaje que sobrevive a un commit perdido.** Si el mensaje se publica y la confirmación falla, el worker recibirá un trabajo que no existe: lo **descarta sin reintentar** (un `404` al tomarlo es «no existe», no «error transitorio»). Se prueba en T5.

## 7. Reintentos, visibilidad y recuperación: valores declarados

Van a configuración con default, y se declaran como **valores elegidos, no medidos**:

| Ajuste | Default | Por qué ese valor |
|---|---|---|
| `DETECTION_MAX_ATTEMPTS` | 3 | Acota el mensaje envenenado sin perder un fallo transitorio |
| `DETECTION_VISIBILITY_TIMEOUT_SECONDS` | 60 | El mensaje vuelve a la cola si el worker muere procesándolo |
| `DETECTION_LEASE_SECONDS` | 300 | Mayor que la visibilidad: un trabajo no se declara huérfano mientras un worker sano todavía puede estar trabajando |
| `ROOMFORGE_DETECTION_SWEEP_SECONDS` | 60 | Frecuencia del barrido |

**Barrido de recuperación.** Un barrido periódico —con el mismo patrón que el refresher de tasas de cambio, que ya corre como tarea de fondo— toma los trabajos `running` con `lease_expires_at` vencido y los devuelve a `pending` republicando, o los marca `failed` si ya agotaron los intentos. **Ésta es la respuesta a R7:** un worker que muere no deja un trabajo atascado para siempre.

## 8. Autenticación del worker

Token de servicio en configuración (`DETECTION_WORKER_TOKEN`), comparado con `secrets.compare_digest`, nunca registrado en logs.

**Fail-closed:** si el token no está configurado, los endpoints del worker **no existen operativamente** (responden error de configuración), igual que el arranque ya falla cerrado cuando falta el secreto de JWT. Un endpoint de worker abierto por descuido sería una puerta para escribir resultados falsos.

## 9. Imagen del worker: separada, para no invalidar el piloto

El servicio de inferencia se dejó **intacto**: su digest identifica el artefacto que produjo la evidencia de F08.2/F08.3, y cambiarlo rompería esa cadena.

El worker usa un Dockerfile propio (`Dockerfile.worker`, contexto `./inference`) que instala las mismas dependencias **más** `boto3` y un cliente HTTP, en un archivo `requirements-worker.txt`. Son dos imágenes con la misma base de inferencia, y el digest del piloto sigue significando lo que decía.

## 10. Cola dedicada y provisionamiento

Cola propia `roomforge-local-detection`, separada de `roomforge-local-events`, para no mezclar eventos de negocio con trabajos de cómputo. Se agrega al script de provisionamiento local, que ya es idempotente y ya crea la otra cola.

## 11. Endpoints

**Personal** (autenticación de personal, autorización por agencia como el resto del catálogo):

| Método y ruta | Rol |
|---|---|
| `POST /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/photos/{photo_id}/detections` | Crea el trabajo (idempotente) y publica. Devuelve el trabajo |
| `GET /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/detections` | Lista los trabajos del inmueble con su estado y resultado: es la observabilidad de R1 |

**Worker** (token de servicio):

| Método y ruta | Rol |
|---|---|
| `POST /api/v1/detection/jobs/{job_id}/claim` | `pending→running`, fija el lease, devuelve el objeto y un enlace firmado de descarga |
| `POST /api/v1/detection/jobs/{job_id}/complete` | Guarda el resultado (`running→completed`), idempotente |
| `POST /api/v1/detection/jobs/{job_id}/fail` | Suma un intento; decide `pending` o `failed` con motivo |

La descarga se resuelve con un **enlace firmado** emitido por la API, no con credenciales de S3 en el worker: el worker sólo puede leer lo que un trabajo autorizado referencia.

## 12. Verificación

**Acá sí hay TDD de producto**, con comportamiento determinista y runner disponible: cada requisito tiene su prueba RED antes del código.

| Requisito | Prueba |
|---|---|
| R1 | Crear devuelve `pending`; completar devuelve `completed` con resultado; ningún estado fuera de los cuatro |
| R2 | Dos peticiones idénticas → mismo id y **un** trabajo; una tercera con el primero `running` tampoco crea otro |
| R3 | Cola que falla al publicar → `503` y un trabajo `pending` sin encolar; el barrido lo republica. Mensaje sin trabajo → el worker descarta sin reintentar |
| R4 | El worker usa el mismo módulo de inferencia y el resultado guarda clase, puntuación, caja y versión de modelo |
| R5 | Mismo mensaje dos veces → un trabajo `completed`, un resultado, mismo conteo de detecciones |
| R6 | Fallo permanente reportado y crasheos repetidos → `failed` al alcanzar exactamente el tope declarado, con motivo; otro sondeo no cambia nada |
| R7 | `running` con lease vencido → el barrido consume un intento y republica, o marca `failed` al llegar al tope; también publica un `pending` nunca encolado |
| R8 | Sin sesión `401`; otra agencia `403`; foto ajena o inexistente `404`; en los tres casos sin trabajo y sin mensaje |
| R9 | El inventario del inmueble no cambia; la superficie no incluye panel ni apps |
| R10 | Todo apunta al endpoint local; sin credenciales reales en el repositorio |
| R11 | El documento del contrato del mensaje coincide con lo que el código publica |
| R12 | El registro distingue lo verificado de lo pendiente |

El worker se prueba sin torch, sin red y sin cola real: la cola, el cliente HTTP y la función de inferencia se inyectan. Eso permite observar RED en cualquier máquina.

## 13. Límites declarados

1. **Floci no es SQS.** La emulación local puede diferir en visibilidad, orden y entrega; nada de lo verificado acá autoriza conclusiones sobre SQS real, que pertenece a F11.
2. **Los valores de §7 son elegidos, no medidos.** No se presentan como óptimos.
3. **Sin interfaz.** La única forma de ver un trabajo hoy es la API. La pantalla es F08.5.
4. **Sin confirmación humana.** Los resultados son sugerencias sin dueño; nada se publica ni se vende con ellos.
5. **Sin retención decidida.** P4 sigue abierta.
