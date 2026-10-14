# Spec — Trabajos asíncronos de detección (F08.4)

Cada requisito es verificable y tiene un criterio observable. Se verifica **por la interfaz pública** (HTTP, cola, base como efecto observable), nunca por almacenamiento interno.

## R1 — Trabajo persistido con estados observables

Un trabajo de detección existe como registro con estado, y ese estado es consultable por el personal autorizado. Los estados son exactamente `pending`, `running`, `completed` y `failed`.

**Aceptación:** tras crear un trabajo, consultarlo devuelve `pending` y nunca `null`; tras un procesamiento exitoso devuelve `completed` con su resultado; tras agotar reintentos devuelve `failed` con el motivo. No existe ningún estado fuera de esos cuatro.

## R2 — Creación idempotente por foto y versión de modelo

Pedir la detección de la misma foto con la misma versión de modelo dos veces **no** crea dos trabajos: devuelve el mismo trabajo.

**Aceptación:** dos peticiones idénticas consecutivas devuelven el mismo identificador de trabajo; el conteo de trabajos para esa foto y versión es **1**. Una tercera petición mientras el primero está `running` tampoco crea otro.

## R3 — Persistir y publicar sin dejar el trabajo mudo

Si la publicación del mensaje falla después de persistir el trabajo, el trabajo **no queda en silencio**: o la operación completa falla sin dejar trabajo, o el trabajo queda en un estado desde el cual la reconciliación lo vuelve a publicar.

**Aceptación:** con una publicación que falla forzadamente, la respuesta al cliente es un error explícito y **o bien** no existe trabajo **o bien** existe uno que no está `completed` y que una reconciliación posterior publica. Nunca un `pending` permanente sin mensaje y sin aviso.

## R4 — El consumidor reutiliza el detector y guarda el resultado

El worker toma el mensaje, descarga **la imagen que el trabajo referencia**, ejecuta el detector existente y persiste el resultado con las detecciones (clase, puntuación y caja) y la versión de modelo usada.

**Aceptación:** procesar un trabajo genera un resultado con al menos las detecciones observadas por el detector sobre esa imagen, y la versión de modelo queda registrada. La lógica de inferencia **no se duplica**: el worker usa el mismo módulo que el CLI del piloto.

## R5 — Duplicar el mensaje no duplica nada (aceptación del plan)

Entregar dos veces el mismo mensaje **no** duplica el trabajo, ni el resultado, ni el conteo de detecciones.

**Aceptación:** procesar el mismo mensaje dos veces deja **un** trabajo en `completed`, **un** resultado, y el mismo número de detecciones que una sola entrega. La segunda entrega no altera el resultado guardado.

> **Interpretación declarada.** La aceptación del plan dice «duplicar mensaje no duplica inventario». El inventario confirmado pertenece a F08.5 y su contrato con F05/F06 no está congelado (§1.5 regla 6), así que aquí «inventario» se verifica como «el trabajo y su resultado persistido». Se cita y se declara en lugar de silenciarlo.

## R6 — Reintentos acotados y fallidos visibles

Los reintentos tienen un tope declarado. Un trabajo que agota el tope queda `failed` con el motivo, y **no se reintenta más**.

**Aceptación:** un trabajo cuya causa de fallo es permanente (por ejemplo, la imagen referenciada no existe) termina en `failed` tras exactamente el número declarado de intentos, con un motivo legible, y un nuevo sondeo de la cola no cambia ese estado.

## R7 — Reiniciar el worker recupera

Un trabajo que quedó `running` porque el worker murió **no queda atascado**: al volver, el sistema lo lleva a un estado final.

**Aceptación:** con un trabajo marcado `running` y sin mensaje en la cola, arrancar el worker lo recupera: termina `completed` o `failed`, nunca permanece `running` indefinidamente.

## R8 — Sólo el personal autorizado encola

Encolar la detección de una foto exige personal autenticado y perteneciente a la agencia dueña del inmueble.

**Aceptación:** sin sesión → `401`; personal de otra agencia → `403`; foto inexistente o de otro inmueble → `404` idéntico al caso de foto inexistente; en todos los casos **ningún trabajo se crea** y ningún mensaje se publica.

## R9 — Sin inventario ni escena

Esta unidad **no** escribe en el inventario comercial (`ListingExtra`) ni en la escena de F06, y no expone interfaz de usuario alguna.

**Aceptación:** el inventario de un inmueble no cambia tras procesar un trabajo, y la superficie modificada no incluye panel ni apps.

## R10 — Sólo local, sin AWS real

La cola y el almacenamiento se ejercitan contra Floci en el stack local. No se usa ni se configura AWS real.

**Aceptación:** los servicios y las pruebas apuntan al endpoint local; ninguna credencial real aparece en el repositorio; los límites de F11 siguen declarados como pendientes.

## R11 — Contrato del mensaje documentado

El mensaje que viaja por la cola queda documentado en `docs/api/` con sus campos, su clave de idempotencia y la versión de modelo, antes de que otra superficie lo consuma.

**Aceptación:** existe el documento, describe el mensaje realmente publicado (verificable contra el código) y declara qué hacer ante un duplicado.

## R12 — Honestidad de la evidencia

Ningún valor no observado se reporta como medido, y ninguna prueba se declara ejecutada sin su salida real.

**Aceptación:** el registro de la unidad distingue lo verificado de lo pendiente; los tiempos y conteos provienen de salidas reales; lo que no se pudo probar (por ejemplo, comportamiento de SQS real frente a Floci) queda dicho como límite.
