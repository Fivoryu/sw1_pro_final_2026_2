# Propuesta: Verificación de correo del cliente

- **Cambio:** `hu003-verificacion-correo`
- **Producto:** RoomForge, SW1 2026-2, Grupo #12
- **Product Backlog:** PB-003 — prioridad Must, complejidad M
- **Historia:** HU-003 — Como cliente, quiero verificar mi correo real con un enlace de activación.
- **Caso de uso:** CU-003 — Verificación de correo real con enlace de activación
- **Requisitos relacionados:** RF-033 y RNF-017
- **Sprint:** Sprint 3
- **Estado del artefacto:** propuesta para aprobación; no representa evidencia de implementación
- **Almacén:** OpenSpec + Engram (híbrido)

## Trazabilidad completa

La propuesta conserva la cadena documental:

**PB-003 → HU-003 → CU-003 → RF-033 → RNF-017 → Sprint 3**

| Nivel | Identificador | Interpretación en esta propuesta |
| --- | --- | --- |
| Product Backlog | PB-003 | Verificación del correo real del cliente; prioridad Must; Sprint 3. |
| Historia de usuario | HU-003 | El cliente activa su cuenta mediante un enlace enviado a su correo. |
| Caso de uso | CU-003 | Emisión, entrega, apertura y consumo de un enlace de activación. |
| Requisito funcional | RF-033 | Enlace de activación de un solo uso y reenvío acotado; reemplaza el modo de correo cualquiera de la demo final. |
| Requisito no funcional | RNF-017 | Enlaces de activación de un solo uso y nunca contraseñas por correo. |
| Sprint | Sprint 3 | Ubicación vigente de PB-003/HU-003/CU-003 en la planificación. |

## Intención, problema y oportunidad

RoomForge ya persiste `correo_verificado`, pero el flujo actual de identidad no exige ese estado para iniciar sesión, no envía un enlace de activación y no dispone de tokens específicos para clientes. En consecuencia, una cuenta registrada con un correo no comprobado puede autenticarse y la demo no demuestra que la cuenta pertenezca a un correo real.

La oportunidad de este cambio es cerrar el flujo mínimo de confianza de la cuenta antes de la demo final: registrar o solicitar la activación, recibir un enlace, activarlo desde la web o desde la app Flutter y recién entonces iniciar sesión. El cambio debe mejorar la confianza sin convertir la activación, el reenvío o los errores de entrega en mecanismos de enumeración de cuentas, spam o reutilización de credenciales.

Esta propuesta no incorpora evidencia externa ni afirma capacidades de un proveedor de correo que no hayan sido verificadas en el repositorio. La investigación externa/proveedor fue declinada; los detalles que sigan sin definición quedan expresados como gaps.

## Usuarios, situaciones y actores

- **Cliente:** registra una cuenta, intenta iniciar sesión, recibe el enlace y activa la cuenta desde la superficie que esté usando.
- **Cliente con cuenta existente no verificada:** intenta iniciar sesión y recibe una oportunidad automática de reenvío, sujeta a los mismos límites.
- **Web:** ofrece una ruta mínima para abrir el enlace, consumirlo y mostrar la confirmación.
- **App cliente Flutter:** recibe el deep link, consume la activación y muestra la confirmación antes de dirigir al login.
- **Backend de identidad:** genera y valida tokens, aplica la política de acceso y los límites de reenvío.
- **Servicio local de demo:** Mailpit ejecutado mediante Docker para visualizar el mensaje durante la demostración.

## Hechos verificados del repositorio

Estos puntos provienen de la exploración de solo lectura y son hechos del estado observado, no resultados de esta propuesta:

1. El router de identidad publica registro, login, refresh, logout y consulta de sesión.
2. `UsuarioGlobal` tiene correo único y `correo_verificado` obligatorio, con valor predeterminado `false`; la migración inicial crea esas columnas.
3. El registro normaliza el correo, hashea la contraseña y crea la cuenta con estado `activo` y correo no verificado.
4. El login actual valida credenciales y estado, pero no controla `correo_verificado`.
5. No se identificó en identidad una entidad ni una migración específica para tokens de verificación de clientes.
6. `Settings` expone `activation_ttl_days` con valor predeterminado de 7 días, pero su uso verificado corresponde a la activación de onboarding de HU-004; no se asume que satisfaga el contrato de HU-003.
7. HU-004 posee un patrón separado de token efímero, hash SHA-256 persistido, notificación posterior a la persistencia y consumo condicional. Es una referencia técnica potencial, no una autorización para compartir entidad, rutas o dominio.
8. La app `apps/cliente_mobile` ya integra registro, login, refresh, logout y sesión. `RegisterScreen` navega actualmente al login después de un registro exitoso y no existe evidencia de pantalla o deep link de activación.
9. `panel/` está en estructura inicial y la exploración no encontró un flujo de verificación de correo.
10. No se identificó un proveedor SMTP/API concreto, outbox, plantilla, URL pública de activación ni mecanismo de deep linking en las superficies consultadas.
11. Las pruebas actuales cubren registro y autenticación, pero no emisión, entrega, expiración, consumo o reenvío de activación.
12. El proyecto declara TDD estricto, pytest, Ruff y Pyright. No se ejecutaron tests, builds, migraciones ni comandos mutantes como parte de la exploración o la propuesta.

## Decisiones de producto confirmadas

Las siguientes decisiones fueron cerradas en la ronda de preguntas y se incorporan como base de la propuesta. Son decisiones de producto, no evidencia de implementación:

1. **Verificación obligatoria:** una cuenta debe tener el correo verificado antes de poder iniciar sesión.
2. **Dos superficies de activación:** el enlace debe funcionar en la web y mediante deep link en la app cliente Flutter.
3. **Resultado exitoso:** la activación muestra una confirmación y dirige al usuario al login; no crea una sesión automáticamente.
4. **Proveedor de demostración:** Mailpit, ejecutado en Docker, será el mecanismo local de demostración.
5. **Respuestas genéricas:** las solicitudes de activación y los tokens inválidos, expirados o consumidos deben responder de forma genérica, sin revelar existencia de cuentas ni el estado interno del token.
6. **Cuentas existentes:** ante el siguiente intento de login de una cuenta no verificada existente, el sistema ofrece un reenvío automático sujeto a límites.
7. **Política del token:** TTL de 7 días, un único token activo, cooldown de 15 minutos, máximo de 3 reenvíos por cada ventana de 24 horas e invalidación del token anterior cuando se emite uno nuevo.
8. **Fallo de entrega:** se informa un error accionable y se permite reintentar, sin eludir el cooldown ni el máximo diario.

## Resultado de producto propuesto

El primer slice debe entregar un flujo completo y comprobable, aislado en el dominio de identidad del cliente:

1. El registro mantiene la cuenta como no verificada y dispara la solicitud de activación sin enviar la contraseña.
2. Una solicitud de activación genera una credencial aleatoria de un solo uso. Solo su representación derivada se persiste; el valor utilizable viaja exclusivamente en el enlace.
3. El login rechaza la creación de una sesión cuando la cuenta aún no está verificada. La respuesta y el contrato de cliente deben permitir orientar al usuario hacia la activación sin revelar información innecesaria.
4. Para una cuenta no verificada existente, un intento de login con credenciales válidas puede iniciar el reenvío automático; un cooldown vigente o el máximo diario impiden el envío y producen una respuesta controlada.
5. La web y la app Flutter consumen el mismo caso de uso de activación. La superficie web abre una ruta de activación y Flutter resuelve el enlace mediante deep link.
6. La activación válida cambia el estado de forma atómica y no puede consumirse dos veces. La confirmación posterior dirige al login en ambas superficies.
7. Un correo inexistente, una solicitud repetida y un token inválido, expirado o consumido no permiten inferir el estado de la cuenta o del token mediante la respuesta pública.
8. Un fallo de Mailpit o del adaptador de entrega no activa la cuenta. El cliente recibe una acción de reintento; cada reintento queda sometido a la política aprobada.

### Decisión operacional propuesta para el reenvío

El reenvío automático debe ocurrir únicamente después de que el backend haya validado las credenciales suficientes para identificar una cuenta no verificada. Los intentos con correo inexistente o contraseña incorrecta no deben disparar envíos. Esta decisión reduce abuso y enumeración, aunque el contrato HTTP y el mensaje exacto permanecen para la fase de especificación.

Para un reintento por fallo de entrega, se recomienda reutilizar el token vigente si todavía es válido y reintentar su entrega, en lugar de crear tokens innecesarios. Si el diseño requiere emitir un token nuevo, deberá invalidar el anterior y contar como reenvío conforme a los mismos límites. La especificación debe fijar la semántica observable y la atomicidad de esta operación.

## Alcance incluido

### Backend y persistencia

- Caso de uso de emisión, entrega, expiración y consumo de activación para `UsuarioGlobal`.
- Entidad o estructura de persistencia específica de HU-003 y migración Alembic aditiva, manteniendo separado el dominio de activación de HU-004.
- Token aleatorio, hash persistido, TTL de 7 días, un token activo, invalidación del anterior y consumo condicional/atómico.
- Cambio del login para exigir `correo_verificado` antes de crear una sesión.
- Reenvío automático para cuentas existentes no verificadas durante su siguiente intento de login, además de la solicitud/reintento que defina el contrato, con cooldown de 15 minutos y máximo de 3 reenvíos en 24 horas.
- Puerto de notificación y adaptador de demo para Mailpit, sin incorporar secretos al código ni a la persistencia.
- Respuestas genéricas para las condiciones aprobadas y errores accionables para fallos de entrega.

### Superficies de cliente

- Estado y UX mínima de registro pendiente de verificación en `apps/cliente_mobile`.
- Resolución del enlace mediante deep link Flutter, consumo de la activación, confirmación y navegación al login.
- Ruta o página web mínima para consumir el enlace, mostrar confirmación y dirigir al login.
- Manejo visible de entrega fallida y acción de reintento respetando los límites.

### Calidad y documentación

- Pruebas TDD del backend para emisión, token válido, expiración, consumo único, concurrencia, reenvío, cooldown, máximo diario, fallo de entrega y regresión de login.
- Pruebas del contrato y del comportamiento de web/Flutter que puedan ejecutarse con el entorno disponible.
- Verificación de que no se persistan ni registren tokens crudos, contraseñas o secretos en las superficies que el repositorio permita inspeccionar.
- Trazabilidad de HU-003 y CU-003 en los artefactos posteriores y en la documentación de Sprint 3.
- Configuración Docker de Mailpit necesaria para la demo, sin afirmar todavía puertos, credenciales, plantilla o URL pública concretos.

## Fuera de alcance y no objetivos

- Activación de administradores, invitaciones, onboarding, tenants o membresías de HU-004.
- Modificaciones de HU-005, HU-006 o del trabajo no versionado preexistente asociado a esas historias.
- Notificaciones generales multi-canal de PB-044; solo el mensaje de activación necesario para HU-003.
- Recuperación o cambio de contraseña, cambio de correo, MFA, perfiles y gestión general de cuentas.
- Proveedor productivo de correo, garantías de entregabilidad externa, colas distribuidas o una plataforma de observabilidad no existente.
- Panel administrativo completo; el alcance web se limita a la activación requerida por HU-003.
- Rediseño general de sesiones, refresh, logout o autorización fuera del bloqueo de login por correo no verificado.
- Cambios en `docs/diagramas/Diagrama1.eapx`, commits, pushes o modificación de los archivos y artefactos preexistentes indicados por el encargo.

## Áreas afectadas e impacto

| Área | Estado verificado | Impacto propuesto |
| --- | --- | --- |
| `backend/app/modules/identity` | Registro y autenticación implementados | Agregar emisión/consumo, reenvío, control de login y contratos sin mezclar HU-004. |
| `backend/app/core/config.py` | Existe configuración y un TTL usado por HU-004 | Incorporar o delimitar configuración de URL, Mailpit, TTL y límites; la reutilización exacta queda para design. |
| `backend/alembic/versions` | Migraciones iniciales de identidad/sesión | Agregar una migración aditiva para la persistencia de HU-003, con downgrade seguro. |
| `backend/tests` | Registro y autenticación cubiertos | Incorporar pruebas TDD y regresiones, incluida la imposibilidad de iniciar sesión antes de activar. |
| `apps/cliente_mobile` | Registro/login/sesión integrados | Cambiar el estado posterior al registro, incorporar deep link, activación, confirmación y reintento. |
| `panel/` o superficie web equivalente | Estructura inicial, sin flujo confirmado | Implementar solo la ruta/página web mínima; la ubicación exacta y el host de demo son gaps técnicos. |
| Docker/infraestructura local | Existe integración Docker para el proyecto | Incorporar Mailpit para la demo y documentar su configuración real cuando se defina. |
| HU-004/HU-005/HU-006 | Trabajo o patrones separados | Mantener aislamiento, evitar renombres compartidos y ejecutar regresiones donde corresponda. |
| Documentación de Sprint 3 | IDs y modelo documental existentes | Añadir trazabilidad y evidencia solo después de ejecutar las pruebas; no presentar esta propuesta como resultado. |

## Criterios de aceptación propuestos

Los siguientes criterios son observables propuestos para la especificación y la implementación. Ninguno está marcado como cumplido:

1. **Registro pendiente:** una cuenta registrada conserva `correo_verificado = false`, no recibe una contraseña por correo y queda asociada a una activación pendiente.
2. **Bloqueo previo:** una cuenta no verificada no puede crear una sesión mediante login; una vez activada, puede iniciar sesión con las credenciales válidas existentes.
3. **Entrega visible de demo:** el mensaje de activación llega a Mailpit y contiene un enlace utilizable dirigido al correo normalizado de prueba.
4. **Activación web:** el enlace abierto en la web activa una cuenta válida, muestra confirmación y dirige al login.
5. **Activación Flutter:** el mismo flujo abierto mediante deep link en la app cliente activa una cuenta válida, muestra confirmación y dirige al login.
6. **Un solo uso:** un token válido activa una sola vez; un segundo intento no cambia nuevamente el estado ni produce una segunda activación efectiva.
7. **Expiración y estados inválidos:** los tokens inválidos, expirados o consumidos generan respuestas genéricas y no activan la cuenta.
8. **Respuesta genérica de solicitud:** una solicitud de activación no permite distinguir públicamente si el correo existe, si ya tiene una solicitud o si el envío fue omitido por límites, según el contrato seguro que se cierre en la especificación.
9. **Reenvío automático:** el siguiente intento de login de una cuenta existente no verificada puede provocar un reenvío automático solo cuando corresponda y sin crear una sesión antes de la verificación.
10. **Límites:** ningún reenvío o reintento supera el cooldown de 15 minutos, el máximo de 3 reenvíos en 24 horas ni la regla de un token activo; la emisión de uno nuevo invalida el anterior.
11. **Fallo recuperable:** si Mailpit o su adaptador falla, la cuenta permanece no verificada, se muestra un error accionable y el reintento aplica los mismos límites.
12. **No filtración:** el token crudo, la contraseña y los secretos no aparecen en respuestas, datos persistidos ni logs inspeccionables por las pruebas o verificaciones del repositorio.
13. **Aislamiento y regresión:** el cambio no modifica el flujo de activación de HU-004 ni rompe el registro, las sesiones o los contratos existentes fuera de la nueva exigencia de verificación.

## Línea base de evidencia de demo propuesta

Esta es la **evidencia mínima defendible propuesta por la coordinación**, no evidencia completada ni una afirmación de que el entorno ya esté preparado:

1. Mensaje visible en Mailpit dirigido al correo de prueba normalizado y con su enlace de activación.
2. Activación exitosa desde la web, con confirmación y llegada al login.
3. Activación exitosa desde Flutter mediante deep link, con confirmación y llegada al login.
4. Intento de login antes de activar bloqueado; intento posterior a activar permitido.
5. Repetición de un enlace y recorridos de token expirado, inválido y consumido: respuestas genéricas y ninguna activación duplicada.
6. Reenvío automático, cooldown, máximo diario y fallo con reintento documentados mediante pruebas o transcriptos reproducibles; el reintento no elude los límites.
7. Inspección de persistencia y logs disponibles para el repositorio que confirme ausencia de token crudo, contraseña y secreto.

La evidencia debe registrar el escenario, el correo de prueba normalizado, el resultado observable y el artefacto de respaldo sin guardar secretos. No se debe completar esta lista con capturas, resultados o métricas hasta que se ejecuten las pruebas y la demo.

## Supuestos

- La columna existente `correo_verificado` seguirá siendo la señal de acceso de la cuenta global; no se reemplaza por una segunda bandera sin justificación en design.
- El registro de una cuenta nueva produce el primer envío de activación; el reenvío automático confirmado se refiere especialmente a cuentas existentes no verificadas.
- La validación de credenciales precede al reenvío automático; los intentos que no validan credenciales no generan correo.
- Mailpit es una dependencia local de demostración y no representa un proveedor productivo ni una garantía de entrega externa.
- La web y Flutter pueden compartir el mismo contrato de activación, aunque la resolución técnica del enlace será específica de cada superficie.
- El valor de 7 días en `Settings` es compatible como punto de partida, pero solo se adoptará para HU-003 después de confirmar su configuración y aislamiento.
- La fase de especificación definirá endpoints, códigos HTTP, cuerpos, mensajes, formato de URL, conteo exacto de reintentos y estrategia de concurrencia sin alterar las decisiones de producto ya confirmadas.

## Dependencias

- Modelo y repositorio actuales de `UsuarioGlobal`, normalización de correo y seguridad de contraseñas.
- SQLAlchemy, PostgreSQL y Alembic para persistencia y migración aditiva.
- Reloj inyectable o equivalente para probar TTL, cooldown y ventanas de 24 horas.
- Configuración Docker capaz de ejecutar Mailpit en el entorno de demo.
- Contrato de navegación web, hosting local y URL de activación aún no identificados.
- Soporte de deep links de la plataforma Flutter/Android y su configuración de rutas.
- Dobles de notificador, repositorio y reloj para TDD, además de regresiones de identidad.
- Revisión de aislamiento con el patrón de activación de HU-004 y con el trabajo de HU-005/HU-006.

## Riesgos y mitigaciones

| Riesgo | Impacto | Mitigación propuesta | Residual/gap |
| --- | --- | --- | --- |
| Fuga o reutilización de token | Activación de cuentas ajenas | Token aleatorio, hash persistido, TTL, consumo atómico, uso único y no registro del valor crudo. | Verificar con pruebas y lectura de persistencia/logs. |
| Bloqueo de login incompatible | Regresiones en contratos actuales | Actualizar explícitamente tests y UX; conservar login posterior a activación y rollback controlado. | El contrato HTTP exacto es GAP-HU003-002. |
| Enumeración de cuentas | Exposición de identidad y abuso | Respuestas genéricas y no enviar ante credenciales inválidas. | Definir códigos/cuerpos sin filtrar estado. |
| Abuso de reenvíos | Spam o agotamiento del canal | Un token activo, invalidación anterior, cooldown de 15 minutos y máximo de 3 en 24 horas. | Definir almacenamiento y zona horaria de la ventana. |
| Consumo concurrente | Doble activación o estado inconsistente | Actualización condicional o bloqueo transaccional y pruebas de carrera. | Estrategia concreta para design. |
| Fallo de Mailpit | Usuario bloqueado sin recuperación | Error accionable y reintento sometido a los mismos límites; no activar antes de entregar. | Configuración/wiring de Mailpit es GAP-HU003-003. |
| Deep link incompleto | Activación imposible desde Flutter | Prueba de enlace en dispositivo/emulador y fallback web documentado. | Ruta y configuración técnica son GAP-HU003-004. |
| Acoplamiento con HU-004 | Regresiones entre actores o dominios | Entidad, puertos, rutas y migración separadas; regresiones específicas. | Revisar interfaces durante design. |
| Secretos en demo | Compromiso o evidencia inválida | Variables de entorno, datos de prueba y revisión de persistencia/logs; nunca secretos en el repositorio. | Proveedor productivo fuera de alcance. |

## Gaps y decisiones técnicas pendientes

La ronda de producto cerró el comportamiento principal, pero no inventa datos técnicos faltantes:

- **GAP-HU003-001:** la matriz relaciona RF-033 con BR-001..022, pero no desglosa las reglas de negocio aplicables a activación. Debe documentarse el mapeo relevante sin atribuir reglas no verificadas.
- **GAP-HU003-002:** faltan endpoints, códigos HTTP, cuerpos, mensajes, contrato web/Flutter y semántica exacta para los estados genéricos y el bloqueo de login.
- **GAP-HU003-003:** faltan proveedor/adaptador concreto, variables de configuración, plantilla, URL pública, wiring Docker de Mailpit y evidencia técnica de entrega. Mailpit está confirmado como decisión de demo, no como configuración ya verificada.
- **GAP-HU003-004:** faltan ruta, esquema de deep link, configuración de plataforma y fallback web.
- **GAP-HU003-005:** la política de exigir verificación y el reenvío automático fueron decididos; aún debe formalizarse su contrato para cuentas nuevas/existentes, credenciales inválidas, cooldown activo y sesión previa.
- **GAP-HU003-006:** TTL y límites fueron fijados como decisión de producto; falta mapearlos a columnas, reloj, contadores, ventana temporal y configuración sin reutilizar accidentalmente HU-004.

No se requiere una nueva ronda de preguntas de producto para avanzar a especificación. Los gaps restantes son de contrato, diseño técnico, configuración y evidencia de ejecución. La investigación externa/provider fue declinada y no debe iniciarse como fase separada.

## Rollback propuesto

1. Si el cambio todavía no está desplegado, revertir de forma coordinada el código de identidad, cliente, web, configuración y migración de HU-003, sin modificar `usuario_global` ni datos de HU-004/HU-005/HU-006.
2. Si ya existe persistencia de tokens, no eliminarla de forma destructiva en un entorno compartido. Revocar o invalidar tokens activos y conservar únicamente los hashes y metadatos necesarios para una migración controlada.
3. Si el diseño incorpora una configuración de enforcement, deshabilitar temporalmente la exigencia de verificación para restaurar el comportamiento anterior de login mientras se corrige el flujo; esa salida no debe marcar cuentas como verificadas.
4. Detener o retirar Mailpit solo del entorno de demo si su configuración falla; no tratar su indisponibilidad como activación válida.
5. Antes de reactivar, ejecutar las regresiones de registro/autenticación y repetir la evidencia mínima, sin conservar enlaces o secretos reales.

El rollback es operativo y reversible: no borra cuentas ni convierte un estado no verificado en verificado. La forma exacta de downgrade y la existencia de un feature flag deben quedar definidas en design antes de aplicar migraciones compartidas.

## Criterios de éxito de la propuesta

La propuesta estará lista para pasar a especificación cuando:

- la trazabilidad PB-003 → HU-003 → CU-003 → RF-033 → RNF-017 → Sprint 3 se conserve en los artefactos posteriores;
- las ocho decisiones de producto confirmadas se reflejen sin contradicciones;
- el alcance incluya backend, web, Flutter, Mailpit de demo, pruebas y seguridad, sin absorber HU-004/HU-005/HU-006;
- los criterios de aceptación y la línea base de evidencia estén identificados como objetivos futuros, no como resultados cumplidos;
- los gaps técnicos queden asignados a spec/design/tasks sin inventar detalles de proveedor;
- el rollback preserve cuentas, datos existentes y separación de dominios;
- la implementación posterior pueda demostrar bloqueo previo, activación en ambas superficies, consumo único, reenvío limitado, recuperación de fallos y ausencia de filtración de secretos.

## Fuentes y clasificación de la información

- **Exploración verificada:** `openspec/changes/hu003-verificacion-correo/explore.md` y observación Engram `3225`, tópico `sdd/hu003-verificacion-correo/explore`.
- **Decisiones confirmadas:** observación Engram `3226`, tópico `sdd/hu003-verificacion-correo/preproposal`, complementada por la ronda de producto recibida para esta fase.
- **Convenciones del repositorio:** `AGENTS.md`, `openspec/project-context.md` y `openspec/config.yaml`.
- **Trazabilidad documental reportada por la exploración:** `docs/sprint-0/ids-trazabilidad.md` y `docs/scrum/sprint-0-requerimientos/04-requerimientos-iniciales.md`.
- **Patrones técnicos observados:** fuentes de identidad, configuración, migraciones, pruebas y activación separada de HU-004 indicadas en la exploración.
- **Información no usada como hecho:** documentación externa, capacidades no verificadas de proveedores, resultados de tests/builds/migraciones y evidencia de demo aún no ejecutada.

## Ronda de preguntas de propuesta

La ronda de preguntas de negocio quedó resuelta antes de cerrar este artefacto. Se incorporaron las decisiones sobre requisito de verificación previa al login, superficies web y Flutter, Mailpit para la demo, comportamiento de éxito, respuestas genéricas, reenvío automático, límites de token y recuperación ante fallos. No se requiere una segunda ronda para avanzar; los pendientes identificados son técnicos u operativos y están registrados como gaps.
