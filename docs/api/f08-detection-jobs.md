# Contrato de trabajos de detección (F08.4)

- **Estado:** implementado en la rama `feat/f08-furniture-ai-pilot`, sin integrar.
- **Alcance:** trabajos asíncronos de detección de mobiliario sobre fotos de inmueble. **No** cubre inventario comercial ni la escena 3D: eso pertenece a F08.5.
- **Entorno:** cola y almacenamiento **locales** (Floci). Esta entrega verifica el contrato del worker con dobles, no ejecuta la integración contra una instancia Floci. Nada de esto describe AWS real.

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
| `POST /claim` | `200` | Si el trabajo está `pending`, pasa a `running`, fija el lease y devuelve el trabajo con `download_url` firmado para su `object_key`. Para un trabajo ya tomado o finalizado devuelve su estado y `download_url: null`, sin volver a tomarlo |
| | `404` | El trabajo no existe; el consumidor descarta el mensaje sin reintentar |
| | `503` | No hay token configurado o no se pudo firmar el enlace; no se procesa la imagen |
| `POST /complete` | `200` | Guarda `model_id` y `detections` (`label`, `score`, `box`) y pasa a `completed`. Repetirlo devuelve el resultado original sin alterarlo |
| | `409` | El trabajo no está `running` o el `model_id` informado no coincide con el trabajo |
| `POST /fail` | `200` | Recibe `{"reason": "..."}`, consume un intento y deja `pending` con republicación o `failed` al agotar `DETECTION_MAX_ATTEMPTS` |
| | `503` | No se pudo republicar; el trabajo persiste como `pending` y el consumidor no confirma el mensaje original |

El worker no recibe credenciales de base de datos ni de S3. Sólo descarga el enlace firmado que devuelve `claim`; el enlace usa el endpoint local de Floci accesible desde la red de Compose. La cola y el almacenamiento de este piloto no apuntan a AWS real.

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

## 6. El mensaje es autosuficiente

El worker no necesita leer el catálogo: el trabajo lleva la `object_key` de la foto, copiada al crear el trabajo. La descarga se resuelve con un enlace firmado emitido por la API, así que el worker nunca recibe credenciales de almacenamiento.

## 7. Qué **no** incluye este contrato

- Escritura en el inventario comercial (`ListingExtra`) ni en la escena de F06: el contrato «sugerencias de IA (F08 ↔ F05/F06)» **no está congelado** (§1.5 regla 6).
- Confirmación humana, descarte o pantalla de revisión (F08.5).
- Reintentos automáticos desde el cliente: los gobierna el servidor.
