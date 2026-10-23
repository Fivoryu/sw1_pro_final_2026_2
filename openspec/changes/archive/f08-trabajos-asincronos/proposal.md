# Proposal — Trabajos asíncronos de detección (F08.4)

- **Cambio:** `f08-trabajos-asincronos`
- **Fase del plan:** F08.4 (`docs/plan-maestro-roomforge.md` §F08)
- **Alcance posterior:** F08.5 y F08.6 quedan fuera y no se simulan
- **Ejecución:** interactiva · **Almacén:** híbrido (OpenSpec + Engram)
- **Presupuesto de líneas modificadas:** 600 (límite del proyecto)
- **Estado de evidencia:** propuesta. Sin implementación, sin migración ejecutada contra PostgreSQL, sin push.

## 1. Resultado y propósito

RoomForge necesita ejecutar la detección de mobiliario **sin que el que la pide espere**, y sin perder trabajos cuando algo falla. Esta unidad entrega:

1. **Un trabajo persistido** con estados observables: `pending`, `running`, `completed`, `failed`, con sus intentos y el motivo del fallo.
2. **Un endpoint de personal** que crea el trabajo de una foto de inmueble, lo publica en la cola y **no deja la ventana abierta** entre persistir y encolar.
3. **Un worker** que toma el mensaje, descarga la imagen autorizada, ejecuta el detector que ya existe y guarda el resultado.
4. **Idempotencia demostrada:** un mensaje duplicado no duplica el trabajo ni su resultado; un reinicio del worker no pierde ni duplica trabajos.
5. **Límites declarados:** reintentos acotados, visibilidad explícita, trabajos fallidos visibles en lugar de perdidos.

## 2. Por qué ahora

F08.1–F08.3 dejaron un detector que funciona pero **sólo se ejecuta a mano, en una terminal**. Eso no es una función de producto: nadie en el flujo real va a correr `docker compose run` para saber qué muebles hay en una foto.

F08.4 es además el puente técnico que el plan ya previó: §1.5 regla 5 autorizó el piloto de inferencia antes de F05/F06, y elegir servidor en F08.3 habilitó esta subfase. Sin ella, F08.5 no tiene de dónde leer sugerencias.

Y es el punto donde el proyecto introduce **por primera vez** una cola de mensajes: hasta hoy conviven en el Compose las variables de SQS y un Floci que lo emula, sin una sola línea de código que los use. Eso convierte esta unidad en la que fija el patrón, para bien o para mal.

## 3. Alcance

**Dentro:**

- Tabla de trabajos con estado, intentos, motivo de fallo, clave de idempotencia y resultado.
- Migración Alembic nueva, siguiendo a `0018_listing_photos`.
- Endpoint de personal que encola el trabajo de una foto, con autorización de agencia como el resto del catálogo.
- Publicación del mensaje en SQS (Floci en local) y recuperación del fallo entre persistir y encolar.
- Worker consumidor que reutiliza `worker3d/detect.py` sin duplicar la lógica del detector.
- Descarga de la imagen autorizada desde S3 con el patrón ya existente.
- Reintentos acotados, visibilidad declarada, marca de fallido con motivo.
- Recuperación de trabajos que quedaron `running` tras un reinicio.
- Pruebas: idempotencia por duplicado, recuperación por reinicio, autorización y estados.

**Fuera:**

- Escribir en el inventario comercial `ListingExtra` o en la escena de F06 (contrato sin congelar, §1.5 regla 6).
- Confirmación humana de sugerencias, pantalla de revisión o interfaz de cualquier tipo (F08.5).
- Ajuste fino, entrenamiento o cambio de modelo (F08.6).
- AWS real: SQS y S3 reales pertenecen a F11. Todo se verifica contra Floci local.
- Cualquier disparador automático al subir una foto: la decisión es del dueño del producto y no está tomada.

## 4. Riesgos y cómo se contienen

| Riesgo | Contención |
|---|---|
| Duplicado de mensaje duplica el resultado | Clave de idempotencia con restricción única en base y verificación explícita en el consumidor |
| Ventana entre persistir y encolar | Estado inicial conocido y reconciliación; la prueba demuestra que un encolado fallido no deja el trabajo mudo |
| Trabajo eternamente `running` tras un reinicio | Recuperación por antigüedad declarada, con prueba de reinicio |
| Reintento infinito sobre un mensaje envenenado | Reintentos acotados y estado `failed` con motivo |
| Descargar imágenes sin autorización | El worker sólo lee la clave que el trabajo referencia, y el endpoint ya valida la pertenencia a la agencia |
| Introducir el patrón de cola de forma que no escale | Documentar el contrato del mensaje y su idempotencia en `docs/api/` antes de que otros lo usen |

## 5. Trazabilidad

- Plan maestro: §F08.4, §1.5 reglas 6 y 7, §5.4.
- Insumo directo: `docs/ai/f08-decision-empaquetado.md` (modalidad servidor) y `odd/tasks/f08-furniture-ai.md` (especificación del piloto).
- El cierre de esta unidad **no** marca F08 completa: F08.5 y F08.6 siguen pendientes.
