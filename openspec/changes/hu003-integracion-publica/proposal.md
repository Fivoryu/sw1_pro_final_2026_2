# Propuesta: Integración pública de HU-003

- **Cambio:** `hu003-integracion-publica`
- **Producto:** RoomForge, SW1 2026-2, Grupo #12
- **Trazabilidad:** `PB-003 → HU-003 → CU-003 → RF-033 → RNF-017 → Sprint 3`
- **Almacén:** híbrido (OpenSpec + Engram)
- **Idioma del artefacto:** español profesional y neutral
- **Modo y entrega:** interactivo; `ask-on-risk`; dos slices no encadenados de aproximadamente 300 líneas cada uno
- **Presupuesto autorizado:** 600 líneas modificadas totales
- **Estado:** propuesta; no constituye evidencia de implementación ni de integración ejecutada

## 1. Intención y resultado de negocio

RoomForge ya dispone de un núcleo de verificación de correo, pero la superficie pública de identidad todavía no lo conecta de manera completa con el registro, el login, la entrega de mensajes ni los clientes. El resultado buscado es que HU-003 deje de ser únicamente una capacidad interna y pueda demostrarse mediante un flujo público acotado: registro pendiente, recepción de un enlace, verificación de un solo uso y acceso posterior.

La propuesta cierra un objetivo académico de Sprint 3, no la construcción de un servicio SaaS productivo. Mailpit y Docker son aceptables como mecanismo local de demostración. No se promete entregabilidad SMTP real, operación multi-réplica, enlaces universales productivos, soporte completo de todas las plataformas ni evidencia de Sprint 3 que todavía no haya sido ejecutada.

La regla de producto principal queda confirmada: **una cuenta con correo no verificado no puede crear una sesión mediante login**. Un intento con credenciales válidas puede iniciar el reenvío automático si la política lo permite, pero nunca crea sesión antes de verificar el correo. La activación válida confirma el correo y orienta al login; no realiza auto-login.

## 2. Trazabilidad y decisiones ya resueltas

| Nivel | Alcance de esta propuesta |
| --- | --- |
| `PB-003` | Verificación del correo real del cliente. |
| `HU-003` | Como cliente, quiero verificar mi correo mediante un enlace de activación. |
| `CU-003` | Emitir, entregar, abrir y consumir un enlace de activación. |
| `RF-033` | Enlace de un solo uso y reenvío limitado. |
| `RNF-017` | No enviar contraseñas ni persistir o exponer el token crudo. |
| `Sprint 3` | Integración pública, pruebas y evidencia únicamente cuando existan resultados reales. |

Se consideran decisiones de producto cerradas para las fases siguientes:

1. El login se bloquea para cuentas no verificadas.
2. Si falla la entrega de correo después del registro, la respuesta al cliente mantiene un resultado genérico de éxito/registro pendiente: no informa el fallo del proveedor ni lo usa para revelar información adicional sobre la cuenta.
3. Las rutas públicas usan nombres en inglés.
4. La ruta viva de registro es `POST /api/v1/auth/register`. Los callers, pruebas y documentación activa ya actualizados no requieren otro renombrado en este cambio.
5. Se conserva el contrato vigente de campos JSON en español, incluyendo los campos existentes de registro (`correo`, `estado`, `correo_verificado`, `creado_en`, entre otros). Cualquier cambio de nombres, estados o forma de respuesta deberá ser aprobado explícitamente en la especificación; esta propuesta no autoriza una migración silenciosa del contrato.
6. Las referencias históricas a `POST /api/v1/auth/registro` se conservan como evidencia histórica y **no deben reescribirse**. No representan la ruta viva.
7. Las respuestas públicas de solicitud y reenvío deben ser genéricas para no revelar si un correo existe, está verificado, está limitado o si el proveedor falló.

## 3. Contrato público que se propone formalizar

La siguiente familia de rutas define el límite funcional de la API para la especificación. Los nombres de los segmentos son deliberadamente ingleses; los cuerpos mantienen el vocabulario JSON existente en español salvo decisión posterior documentada.

| Operación | Ruta pública propuesta | Resultado observable |
| --- | --- | --- |
| Registro | `POST /api/v1/auth/register` | Conserva el resultado y los campos vigentes; deja la cuenta pendiente y orienta a revisar el correo sin revelar el resultado del proveedor. |
| Login | `POST /api/v1/auth/login` | Mantiene el contrato de sesión para cuentas activas y verificadas; no crea sesión para una cuenta no verificada. |
| Solicitud | `POST /api/v1/auth/email-verification/request` | Acuse genérico, sin confirmar existencia, estado ni entrega. |
| Reenvío | `POST /api/v1/auth/email-verification/resend` | Mismo tratamiento genérico y mismos límites que la solicitud. |
| Consumo | `POST /api/v1/auth/email-verification/consume` | Consume el token recibido en el enlace; activa una sola vez y devuelve confirmación sin crear sesión. |

La especificación deberá fijar códigos HTTP, cuerpos completos, validaciones estructurales y mensajes exactos. Como orientación de seguridad, solicitud y reenvío deben compartir una respuesta genérica; un token inválido, vencido, invalidado o ya consumido no debe diferenciarse públicamente. El token no debe aparecer en respuestas, logs, persistencia ni mensajes de error. La ruta de registro no debe incluir contraseña ni token en el mensaje de activación.

El cambio de `/registro` a `/register` es una condición de línea base ya resuelta y no una tarea de implementación de esta propuesta. No se tocarán referencias históricas para hacerlas coincidir con la ruta actual.

## 4. Alcance por slices

### Slice 2A — Backend público, registro/login y seam de notificación

**Límite:** hasta aproximadamente 300 líneas modificadas. Es un límite de seguridad del slice, no una estimación ya medida.

Incluye exclusivamente:

- Formalizar e implementar el contrato HTTP público de solicitud, reenvío y consumo de verificación.
- Conectar el núcleo existente de verificación al registro, conservando la cuenta como no verificada y la respuesta JSON vigente en español.
- Conectar el guard de login: validar credenciales y estado antes de crear sesión; bloquear cuentas no verificadas y aplicar el reenvío automático únicamente cuando corresponda.
- Mantener la respuesta genérica cuando la entrega posterior al registro falla; la cuenta no se marca como verificada.
- Exponer un puerto/adaptador de notificación desacoplado del caso de uso y un seam sustituible por fake en las pruebas.
- Agregar únicamente la configuración mínima y segura necesaria para una entrega local con Mailpit, sin secretos y sin convertir Mailpit en un proveedor productivo.
- Incorporar la extensión mínima de infraestructura local solo si puede realizarse sin alterar configuraciones OpenSpec ni reestructurar el entorno existente.
- Agregar pruebas de contrato y regresión para registro, login, respuestas genéricas, notifier y ausencia de token/contraseña en las superficies inspeccionables.

El núcleo archivado ya observado —modelos, repositorio, política, migración y pruebas internas— no se reimplementa ni se copia. Solo se corrige si la integración demuestra una incompatibilidad imprescindible, dejando la razón y el impacto documentados. No se alteran las reglas de HU-004 ni las configuraciones OpenSpec del root o del backend.

**Salida requerida de 2A:** API pública utilizable y testeable por clientes, con la política de bloqueo de login y un seam de entrega local. La presencia de un fake notifier no equivale a evidencia de entrega en Mailpit.

### Slice 2B — Integración Flutter/web factible y evidencia

**Límite:** hasta aproximadamente 300 líneas modificadas. No es una autorización para crear una aplicación web desde cero.

Incluye solo lo que las superficies existentes permitan integrar de forma segura:

- Flutter: modelos, servicio/repositorio o extensión mínima de la capa de autenticación, estado de activación, pantallas mínimas de confirmación/solicitud, rutas públicas y actualización de la orientación posterior al registro.
- Flutter: recepción del enlace y consumo mediante deep link únicamente si el `go_router`, el entrypoint y la configuración de plataforma existentes admiten una integración verificable dentro del límite. El token se procesa en memoria y no se persiste como credencial.
- Web: ruta/página pública mínima para consumir el enlace y dirigir al login únicamente si el submódulo `panel/` tiene un scaffold, entrypoint, router y runner reales que puedan confirmarse al iniciar el slice.
- Pruebas de contrato, routing, manejo de estados y seguridad que estén soportadas por los runners reales de Flutter o web.
- Evidencia de integración separada por tipo: fake, backend, Mailpit, Flutter, web y evidencia documental de Sprint 3. Cada resultado debe ser ejecutado o marcado como no disponible con su causa.

**Decisión de límite del panel:** si `panel/` continúa sin scaffold materializado, no se reconstruirá un panel ni se ocultará esa ampliación dentro de las 300 líneas. Se podrá completar la parte Flutter y la evidencia disponible, dejando la página web como gap explícito, o detener el slice completo si la ausencia del panel impide verificar un resultado público coherente. La elección concreta debe registrarse antes de editar.

No se prometen Universal Links/App Links productivos. Sin dominio, certificados, fingerprints, Team ID y archivos de asociación verificables, el máximo académico es un deep link local con fallback web; si tampoco puede probarse en el emulador/dispositivo disponible, se documentará como no disponible y no como completado.

## 5. Límites de presupuesto y condición de detención

Los dos slices son independientes y no encadenados. El presupuesto agregado es de 600 líneas modificadas, aproximadamente 300 para 2A y 300 para 2B. El conteo real debe incluir adiciones y eliminaciones authored de código, configuración de ejecución y pruebas relevantes; no se debe esconder una ampliación bajo documentación o archivos generados.

Se detendrá el trabajo y se solicitará una decisión explícita si ocurre cualquiera de estas condiciones:

- un slice supera su límite orientativo o el total amenaza con superar 600 líneas;
- mantener seguridad, pruebas y separación de HU-004 exigiría comprimir requisitos esenciales;
- `panel/` no tiene scaffold y crear uno sería necesario para afirmar integración web;
- no existe un runner o entorno mínimo para comprobar la superficie que se pretende declarar;
- la configuración de Mailpit exige cambios de infraestructura mayores que el seam local aprobado;
- el contrato actual no permite conectar registro/login sin romper campos JSON, sesiones existentes o la ruta viva `register`.

Ante la detención, no se elegirán silenciosamente excepciones de tamaño, no se crearán PRs encadenados y no se modificará el gitlink del submódulo. El resultado debe indicar qué slice quedó parcial, qué líneas y archivos motivaron el corte y qué decisión de producto/técnica falta.

## 6. Fuera de alcance y no objetivos

- Reabrir, editar o reimplementar el cambio archivado `hu003-verificacion-correo`.
- Modificar `hu003-verificacion-correo`, `hu-004` u otras historias, sus gitlinks, sus migraciones o sus artefactos históricos.
- Alterar `openspec/config.yaml`, `openspec/project-context.md`, configuraciones OpenSpec del backend o cualquier configuración de coordinación raíz.
- Cambiar nuevamente la ruta viva de registro o reescribir referencias históricas a `/api/v1/auth/registro`.
- Crear un proveedor SMTP productivo, garantizar entregabilidad externa, agregar outbox, workers, colas distribuidas, Redis u observabilidad nueva.
- Enviar contraseñas, persistir tokens crudos, registrar query strings de activación o diseñar mecanismos de enumeración de cuentas.
- Revocar automáticamente sesiones ya existentes, rediseñar refresh/logout/me o modificar autorización no relacionada con el bloqueo de nuevos logins.
- Crear un panel web completo, reemplazar un scaffold existente o implementar frontend web si no existe un punto de integración real.
- Prometer deep links productivos, Universal Links, App Links, integración móvil completa o compatibilidad de plataforma sin build/prueba verificable.
- Completar documentación o evidencia de Sprint 3 con capturas, métricas o resultados no ejecutados.
- Modificar código en esta fase de propuesta, crear commits, hacer push o cambiar ramas.

## 7. Áreas afectadas e impacto

| Área | Impacto previsto |
| --- | --- |
| Backend identidad | Contrato público, wiring de registro/login y adaptador de notificación, sin duplicar el núcleo archivado. |
| Persistencia existente | Se reutiliza el núcleo ya presente; cualquier ajuste imprescindible debe ser aditivo y justificado. No se toca el dominio de HU-004. |
| Infraestructura local | Mailpit puede incorporarse como dependencia de demo si el entorno lo admite; no implica soporte productivo. |
| Cliente Flutter | Cambia la orientación posterior al registro y agrega activación solo en las capas existentes y verificables. |
| Panel web | Impacto condicional al scaffold real; ausencia de scaffold es un bloqueo de alcance, no una invitación a reconstruirlo. |
| Pruebas | Regresiones de identidad y pruebas de contrato; la evidencia real de Docker, Flutter, web y Mailpit depende de disponibilidad. |
| Documentación Sprint 3 | Solo se actualizará en una fase posterior con resultados trazables; esta propuesta no afirma cumplimiento. |
| Equipos y operación académica | Backend se integra primero; Flutter/web consumen el contrato estable. La demo usa datos locales y no representa operación SaaS. |

## 8. Dependencias y orden de trabajo

1. **Especificación:** fijar cuerpos, códigos, mensajes, estados genéricos, campos JSON, formato del enlace y semántica del reenvío sin contradecir las decisiones cerradas.
2. **Diseño:** confirmar los puntos de inyección existentes, la transacción registro-notificación, la configuración Mailpit y la viabilidad real de Flutter y del panel.
3. **Slice 2A:** implementar y probar backend antes de cambiar clientes; validar que el fallo de entrega no crea una cuenta verificada ni altera la respuesta pública genérica.
4. **Slice 2B:** inspeccionar primero el scaffold web y la disponibilidad de Flutter; integrar únicamente las superficies que puedan probarse dentro del presupuesto.
5. **Verificación:** ejecutar los runners disponibles por repositorio y separar evidencia fake de evidencia real. La indisponibilidad de Docker, Mailpit, Flutter, Node, emulador o dispositivo debe quedar registrada como gap.
6. **Cierre:** actualizar trazabilidad y Sprint 3 solo con evidencia efectivamente obtenida.

Dependencias técnicas conocidas: `UsuarioGlobal.correo_verificado`, servicios y repositorios actuales de identidad, configuración de API del cliente móvil, `go_router`, PostgreSQL/Alembic, el puerto de notificación y un entorno local capaz de ejecutar Mailpit. El panel requiere confirmar `package.json`, entrypoint, router, package manager y scripts antes de prometer archivos o comandos.

## 9. Riesgos y mitigaciones

| Riesgo | Impacto | Mitigación | Señal de detención |
| --- | --- | --- | --- |
| Fuga o reutilización del token | Activación indebida y violación de RNF-017 | Hash persistido, token efímero, consumo atómico, no persistencia ni logs sensibles. | Si el contrato o cliente requiere guardar el token crudo. |
| Login no verificado rompe consumidores | Regresión de autenticación | Mantener respuestas y campos vigentes, actualizar pruebas y probar que no se crea sesión antes de activar. | Si no puede aislarse la nueva regla sin rediseñar sesiones. |
| Enumeración mediante errores de correo | Exposición de cuentas y abuso | Acuses genéricos para solicitud/reenvío y fallo de entrega; reenvío automático solo después de credenciales válidas. | Si el proveedor obliga a reflejar su error al cliente. |
| Mailpit no disponible | Demo incompleta o falso sentido de entrega | Seam fake para pruebas unitarias y evidencia real separada; registrar `N/A` cuando el entorno no exista. | Si se necesita infraestructura productiva para continuar. |
| Panel vacío o no verificable | Sobreconsumo del slice 2B | No crear scaffold; completar solo Flutter/evidencia posible o detener según impacto. | Ausencia de entrypoint/runner que impida una integración segura. |
| Deep link no comprobable | Activación móvil no demostrable | Mantener fallback web y declarar el soporte según la plataforma realmente probada. | Sin build, emulador o dispositivo para verificarlo. |
| Acoplamiento con HU-004 | Regresiones de dominio y migraciones | Mantener bounded context, tablas, rutas y configuración separados; ejecutar regresiones. | Si la integración exige compartir entidades o cambiar el flujo archivado. |
| Exceso de líneas | Revisión insegura y pérdida de alcance | Conteo por slice, dos slices no encadenados, `ask-on-risk` y corte explícito. | >300 por slice o amenaza al total de 600. |
| Evidencia académica incompleta | Declaración no defendible de Sprint 3 | Clasificar evidencia por fuente y registrar gaps; no convertir archivos presentes en PASS. | Si solo existe evidencia documental sin ejecución. |

## 10. Rollback y compatibilidad

- **Slice 2A:** retirar de forma coordinada los endpoints, wiring y adaptador agregados por este cambio, manteniendo intactos el núcleo archivado ya presente, los datos de usuarios y el contrato vivo `register`. Si se hubieran agregado datos de integración, invalidar tokens activos antes de cualquier limpieza; no eliminar cuentas, sesiones ni datos de HU-004.
- **Slice 2B:** revertir únicamente rutas, pantallas, servicios y componentes agregados en Flutter/web. El backend puede permanecer con su contrato si ya está siendo utilizado por otros clientes; la reversión no debe cambiar la semántica de cuentas verificadas.
- **Fallo de entrega:** nunca equivale a verificación. La cuenta permanece no verificada y el usuario conserva un camino genérico de reintento sujeto a cooldown y límites.
- **Fallo de infraestructura local:** detener Mailpit solo en el entorno de demo y conservar el resultado como no disponible; no sustituirlo por una afirmación de entrega real.
- **Rollback operativo:** si el enforcement de login necesita deshabilitarse temporalmente, debe ser una decisión explícita de operación y no marcar cuentas como verificadas. No se autoriza crear ese mecanismo modificando configuraciones OpenSpec.
- La ruta histórica `/api/v1/auth/registro` no se elimina de documentos históricos durante el rollback ni se usa como sustitución automática de la ruta viva `/api/v1/auth/register`.

## 11. Criterios de éxito verificables

Estos son resultados objetivo para fases posteriores; ninguno se declara cumplido por la presente propuesta.

1. La trazabilidad `PB-003 → HU-003 → CU-003 → RF-033 → RNF-017 → Sprint 3` aparece sin contradicciones en los artefactos posteriores.
2. El registro en `POST /api/v1/auth/register` conserva los campos JSON vigentes en español, deja `correo_verificado` en `false` y ofrece orientación genérica, sin token ni contraseña.
3. Un fallo posterior de Mailpit no expone el proveedor, no convierte la cuenta en verificada y no cambia el resultado público genérico de registro pendiente.
4. Una cuenta no verificada no crea sesión en login; una cuenta verificada conserva el flujo normal de sesión.
5. Solicitud y reenvío no permiten distinguir públicamente correo inexistente, cuenta verificada, límite alcanzado o fallo de entrega.
6. El consumo válido activa una sola vez, no realiza auto-login y proporciona una ruta clara hacia login; tokens inválidos, vencidos o consumidos no cambian el estado.
7. Slice 2A permanece dentro de 300 líneas modificadas y deja pruebas de contrato/regresión reproducibles.
8. Slice 2B solo declara como completadas las superficies Flutter/web que tengan scaffold, runner y plataforma efectivamente verificables; si el panel no tiene scaffold, el gap queda explícito.
9. La evidencia de Mailpit, deep link, web, Flutter y Sprint 3 se presenta por separado y con resultado real, `N/A` o bloqueo justificado; nunca se infiere PASS por presencia de archivos.
10. El total permanece dentro de 600 líneas. Si no es posible, el trabajo se detiene y solicita decisión antes de continuar.

## 12. Gaps abiertos y siguiente fase

Persisten gaps técnicos y de entorno, no nuevas preguntas de producto: códigos y cuerpos HTTP definitivos, punto exacto de inyección del notifier, parámetros de Mailpit, scaffold del panel, recepción de deep links en cold start/resume, runners disponibles y evidencia de Sprint 3. La fase de especificación debe convertirlos en contratos comprobables sin cambiar las decisiones de producto cerradas.

La siguiente acción recomendada es **`spec`**. No se debe ejecutar `apply` desde esta propuesta ni tratar sus criterios como resultados ya obtenidos.

## Fuentes y clasificación

- `openspec/changes/hu003-integracion-publica/explore.md`: exploración dirigida y estado técnico observado.
- Observación Engram `sdd/hu003-integracion-publica/explore`: cross-check persistido de la exploración.
- Código, pruebas y documentación de backend, Flutter, panel e infraestructura citados en la exploración.
- Cambio archivado `hu003-verificacion-correo`: referencia histórica y fuente de decisiones heredadas; no se modifica.
- Decisiones de producto comunicadas para esta fase: bloqueo de login no verificado, respuesta genérica ante fallo de entrega, rutas públicas en inglés, ruta viva `register` y preservación del contrato JSON en español.

La clasificación se mantiene explícita: hechos provienen de la exploración; decisiones de producto provienen de la sesión; los criterios, límites y gaps de este documento son propuesta para especificación, implementación y verificación posteriores.
