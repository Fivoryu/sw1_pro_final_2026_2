# Contrato de trabajos de detección (F08.4)

- **Estado:** implementado en la rama `feat/f08-furniture-ai-pilot`, sin integrar.
- **Alcance:** trabajos asíncronos de detección de mobiliario sobre fotos de inmueble. **No** cubre inventario comercial ni la escena 3D: eso pertenece a F08.5.
- **Entorno:** cola y almacenamiento **locales** (Floci). El comportamiento del worker/API se prueba con dobles y también se registró una ida y vuelta real de la cola con `SqsJobQueue`; no se ejecutó el ciclo completo API → descarga firmada → inferencia del contenedor → resultado contra Floci. Nada de esto describe AWS real.

## 1. Rutas de personal

Prefijo: `/api/v1/staff/agencies/{agency_id}/listings/{listing_id}`. Exigen sesión de personal y pertenencia a la agencia, como el resto del catálogo.

| Método y ruta | Código | Resultado |
|---|---|---|
| `POST /photos/{photo_id}/detections` | `201` | Trabajo creado y encolado |
| | `200` | Repetición: ya existía un trabajo para esa foto y modelo. Vuelve a publicar si el anterior nunca se encoló |
| | `401` | Sin sesión de personal |
| | `403` | Personal de otra agencia |
| | `404` | Inmueble inexistente, o foto que no pertenece a ese inmueble |
| | `409` | La foto no está confirmada |
| | `503` | La cola rechazó el mensaje. **El trabajo queda persistido como `pending` y se republica en el siguiente intento** |
| `GET /detections` | `200` | Lista de trabajos del inmueble con estado, intentos y resultado |

**Detalle importante sobre los `5xx`.** El proyecto sanea los cuerpos de error `5xx` con un manejador global: un `503` **no** devuelve el detalle interno, devuelve `{"detail": "A required dependency is unavailable", "code": "dependency_unavailable"}`. El contrato con el cliente es el **código de estado**; el job se identifica consultando `GET /detections`.

## 2. Rutas del worker

Prefijo: `/api/v1/detection/jobs/{job_id}`. Las tres rutas exigen `Authorization: Bearer <DETECTION_WORKER_TOKEN>`. El token es de servicio, se compara en tiempo constante y no se registra. Si `DETECTION_WORKER_TOKEN` no está configurado, las rutas fallan cerrado con `503`; un token ausente o incorrecto recibe `401`.

| Método y ruta | Código | Resultado |
|---|---|---|
| `POST /claim` | `200` | Si el trabajo está `pending`, pasa a `running`, fija el lease y devuelve el trabajo con `download_url` firmado para su `object_key` y un `claim_token` opaco. Para un trabajo ya tomado o finalizado devuelve su estado y `download_url: null`, sin volver a tomarlo ni entregar un token |
| | `404` | El trabajo no existe; el consumidor descarta el mensaje sin reintentar |
| | `503` | No hay token configurado o no se pudo firmar el enlace; no se procesa la imagen. Si el claim ya se adquirió, la respuesta de firma fallida incluye `X-Detection-Claim-Token` para que el worker consuma el intento mediante `POST /fail` |
| `POST /complete` | `200` | Recibe `claim_token`, `model_id` y `detections` (`label`, `score`, `box`); guarda el resultado sin persistir el token y pasa a `completed`. Repetirlo con el mismo token devuelve el resultado original sin alterarlo |
| | `409` | El token no corresponde al claim vigente, el trabajo no está `running` o el `model_id` informado no coincide con el trabajo |
| `POST /fail` | `200` | Recibe `{"claim_token": "...", "reason": "..."}`, consume un intento y deja `pending` con republicación o `failed` al agotar `DETECTION_MAX_ATTEMPTS` |
| | `409` | El token no corresponde al claim vigente; el estado del trabajo no cambia |
| | `503` | No se pudo republicar; el trabajo persiste como `pending` y el consumidor no confirma el mensaje original |

Cada claim exitoso genera un `claim_token` nuevo y lo guarda en la columna `claim_token` del trabajo. El worker debe incluirlo en `complete` o `fail`; tras vencer un lease y reclamarse el trabajo, cualquier reporte con el token anterior recibe `409` sin cambiar estado, intentos ni resultado. Un token que no puede codificarse como UTF-8 (por ejemplo, un surrogate aislado) también recibe `409` y no altera el trabajo. Si el publicador marca cero filas porque el worker ya reclamó el mensaje, la API relee y acepta `running` con la misma generación de `attempts` como publicación exitosa, no devuelve un `503` espurio. Si falla la firma del enlace tras guardar el claim, la API mantiene el trabajo `running`, devuelve el token en `X-Detection-Claim-Token` y el worker informa el error por `POST /fail`; así se consume el intento y se publica un mensaje nuevo o se alcanza `failed` al tope.

El worker no recibe credenciales de base de datos ni de S3. Sólo descarga el enlace firmado que devuelve `claim`; el enlace usa el endpoint local de Floci accesible desde la red de Compose. El productor y el consumidor rechazan endpoints SQS ausentes o no locales antes de crear el cliente boto3. El almacenamiento S3 también exige un endpoint configurado local por defecto, y sus clientes locales usan credenciales placeholder explícitas para no consultar la cadena ambiental de AWS. `S3_ALLOW_REMOTE_ENDPOINT` permanece en `false`; si se habilita, deben configurarse explícitamente `S3_ACCESS_KEY_ID` y `S3_SECRET_ACCESS_KEY`, que se pasan directamente a boto3. Sin ambas credenciales el almacenamiento remoto falla cerrado y nunca se delega en la cadena ambiental. F11 es la fase que habilitaría endpoints remotos de manera explícita. La cola y el almacenamiento de este piloto no apuntan a AWS real.

## 3. Estados

`pending`, `running`, `completed`, `failed`. Son los únicos cuatro; la base los impone con una restricción.

```
pending ──(claim)──▶ running ──(complete)──▶ completed
   ▲                    │
   └──(fail con intentos restantes)──┤
                                      └──(intentos agotados)──▶ failed
```

## 4. Idempotencia

Un trabajo por **foto y versión de modelo**. La clave es `f"{photo_id}:{model_id}"` (`dedupe_key`) y tiene una **restricción única en la base**: es la última línea de defensa contra un trabajo duplicado cuando la cola entrega el mismo mensaje dos veces.

Consecuencia para el cliente: pedir dos veces la detección de la misma foto es seguro. La segunda devuelve `200` con el mismo `job_id`.

## 5. Contrato del mensaje

Lo que viaja por la cola (`roomforge-local-detection`), publicado por la API:

```json
{
  "version": 1,
  "job_id": "<uuid del trabajo>",
  "photo_id": "<uuid de la foto>",
  "object_key": "agencies/<agency>/listings/<listing>/photos/<photo>",
  "model_id": "ssdlite320-mobilenetv3-coco-v1",
  "attempt": 1
}
```

Campos serializados en JSON compacto y con claves ordenadas, para que el cuerpo sea estable y comparable.

**Qué hacer ante un duplicado:** el consumidor **relee el estado del trabajo antes de trabajar**. Si ya está `completed`, no vuelve a inferir ni a informar y descarta el mensaje. La entrega repetida es normal, no un error.

**Qué hacer cuando el trabajo no existe:** descartar el mensaje **sin reintentar**. Un mensaje puede sobrevivir a una confirmación perdida; reintentarlo sería trabajo infinito por un trabajo que nunca existió.

**Fallo de claim no-404 sin token:** el worker conserva la entrega para reintento hasta que `ApproximateReceiveCount` supera `DETECTION_MAX_ATTEMPTS`; entonces registra el fallo en su log y elimina el mensaje. El trabajo no se modifica desde el worker. El barrido de la API republica un `pending` sin marca o cuya marca `enqueued_at` tenga al menos `DETECTION_LEASE_SECONDS` de antigüedad (300 s por defecto); una marca reciente espera el lease completo, así no se publica otra copia en cada barrido de 60 s. Una marca vieja se limpia antes de publicar, de modo que un fallo de cola también deja el trabajo recuperable. Esto recupera también la ruta capped-drop: el worker puede borrar la entrega dejando intacta una marca vieja, pero el estado `pending` vuelve a ser seleccionado por antigüedad.

El provisionamiento local lee la misma variable de entorno `DETECTION_MAX_ATTEMPTS` que el worker y configura `roomforge-local-detection-dlq.maxReceiveCount` como ese valor más una recepción; con la variable ausente, ambos usan 3. La recepción adicional permite al worker observar y eliminar la entrega al superar su límite; el DLQ queda como destino de mensajes que el consumidor no logra eliminar.

## 6. El mensaje es autosuficiente

El worker no necesita leer el catálogo: el trabajo lleva la `object_key` de la foto, copiada al crear el trabajo. La descarga se resuelve con un enlace firmado emitido por la API, así que el worker nunca recibe credenciales de almacenamiento.

## 7. Qué **no** incluye este contrato

- Escritura en el inventario comercial (`ListingExtra`) ni en la escena de F06: el contrato «sugerencias de IA (F08 ↔ F05/F06)» **no está congelado** (§1.5 regla 6).
- Confirmación humana, descarte o pantalla de revisión (F08.5).
- Reintentos automáticos desde el cliente: los gobierna el servidor.
