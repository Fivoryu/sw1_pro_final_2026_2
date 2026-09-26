# Redefinición de RoomForge: alcance, decisiones y ruta de validación

> **Respuesta:** Sí, podemos avanzar a implementación por etapas, comenzando con validaciones técnicas acotadas. Esto no demuestra todavía que el producto completo sea factible en un mes, que todas las tecnologías funcionen en conjunto ni que se haya cerrado el alcance del MVP.
>
> Este documento consolida lo acordado en la conversación y las recomendaciones para poder decidir el siguiente paso sin borrar la propuesta original ni presentar hipótesis como decisiones.

## Cómo leer este documento

| Marca | Significado |
|---|---|
| **ACORDADO** | Requisito o límite expresado y confirmado por el usuario. |
| **RECOMENDADO** | Alternativa técnica sugerida; no se considera aprobada por aparecer aquí. |
| **PENDIENTE** | Decisión humana o validación empírica que todavía hace falta. |
| **CONTEXTO** | Dato comunicado o hallazgo citado; no equivale a benchmark ni a prueba del producto. |

Las recomendaciones son advisory-only. La implementación posterior deberá convertir las decisiones seleccionadas en requisitos comprobables, respetar la trazabilidad existente y registrar los cambios de alcance sin reciclar identificadores.

## 1. Continuidad y relación con la propuesta original

La [propuesta original de RoomForge](propuesta-roomforge-original.md) se conserva sin modificación. Describe captura de espacios con teléfono, asistencia local de IA y reconstrucción 3D asíncrona, y debe seguir leyéndose como antecedente, no como especificación completa de esta redefinición.

La [infraestructura del Sprint 0](scrum/sprint-0-requerimientos/09-infraestructura.md) también conserva su valor histórico. Documenta FastAPI, PostgreSQL, S3/SQS, Floci, Meshroom, Hardhat y una topología AWS prevista; no prueba por sí sola que cada componente esté implementado, desplegable o siga siendo la selección adecuada.

| Tema | Continuidad o ajuste planteado | Estado |
|---|---|---|
| Captura de interiores con Android | Se conserva como origen de geometría y contenido del inmueble. | **ACORDADO**, con método por validar. |
| Asistencia y reconstrucción fotogramétrica con Meshroom | La asistencia de captura sigue siendo una posibilidad; sustituir la reconstrucción obligatoria por geometría paramétrica simple es una recomendación para reducir riesgo. | **PENDIENTE** de reconciliar con la propuesta anterior. |
| Modelo externo/open-source y ajuste local | Se acepta evaluar y reutilizar pesos preentrenados; no se aprobó un modelo ni se autorizó afirmar entrenamiento propio. | **ACORDADO** como enfoque; selección pendiente. |
| Inferencia IA offline en el teléfono | La propuesta original la plantea; ubicar la inferencia en PC/servidor/AWS cambiaría ese requisito. | **PENDIENTE**. |
| SaaS inmobiliario | El nuevo alcance agrega catálogo, agencias, publicación, reservas y token de prueba. | **ACORDADO** como dirección del producto. |
| Suscripciones y alta pagada de agencias | No forman parte del MVP replanteado: el alta de agencia no se vende ni se automatiza. | **ACORDADO** para este alcance; los artefactos históricos no se reescriben aquí. |
| Plazo y tamaño del equipo | Se informó un mes y dos desarrolladores como límite de planificación. | **ACORDADO** como restricción reportada; no es un compromiso de factibilidad. |

La [matriz histórica de IDs](sprint-0/ids-trazabilidad.md) contiene historias, objetivos y decisiones anteriores que pueden discrepar del alcance aquí descrito (por ejemplo, suscripciones, Meshroom y cronograma). Esta redefinición no actualiza esa matriz, no cierra GAPs y no crea IDs nuevos. La reconciliación documental y de backlog deberá hacerse deliberadamente antes de comprometer trabajo de producto.

## 2. Producto y límites del MVP replanteado

**ACORDADO:** RoomForge evolucionará de una propuesta de escaneo a un SaaS inmobiliario multi-tenant con capturas de agentes, catálogo para clientes, recorridos 3D sencillos y reservas comerciales con token de prueba.

**ACORDADO:** el modelo espacial de primera entrega se limita a inmuebles completos de un solo piso, compuestos por varios ambientes conectados manualmente. No se incluye escaneo de escaleras, unión automática de pisos ni reconstrucción fotorrealista.

**ACORDADO:** el objetivo visual son volúmenes y primitivas 3D simples, editables y suficientes para comprender la distribución. El agente podrá corregir dimensiones y objetos; la captura automática no debe presentarse como medición exacta.

**ACORDADO:** se construirán superficies separadas para:

1. Una app Android de captura para el agente.
2. Una app móvil del cliente para explorar y reservar.
3. Un panel web administrativo para la plataforma y las agencias.

**PENDIENTE:** la división exacta de funciones entre apps, el acceso a edición desde web/móvil y la aprobación final del catálogo de alcance.

### Actores y responsabilidades

| Actor | Responsabilidad acordada |
|---|---|
| Administrador de plataforma | Crea agencias y sus administradores; no se incorpora onboarding automático de pago para agencias en el MVP. |
| Administrador de agencia | Administra el contenido de su agencia y aprueba o rechaza publicaciones preparadas por agentes. |
| Agente | Prepara borradores con fotos, ambientes, muebles y precios; puede corregir geometría y objetos. |
| Cliente | Busca inmuebles, consulta el recorrido y la oferta, y puede crear una reserva pendiente mediante wallet externa. |

El aislamiento multi-tenant debe proteger los datos privados y las operaciones administrativas de cada agencia frente a otras agencias. En cambio, las publicaciones aprobadas del catálogo son deliberadamente visibles para clientes de manera transversal entre agencias. Se deben probar ambos lados: impedir acceso cruzado a datos privados y permitir consultar publicaciones públicas sin exponer información de gestión.

## 3. Publicaciones, catálogo y precios

El agente prepara una publicación en borrador. El administrador de agencia debe aprobarla antes de que sea visible para clientes. La edición de la publicación no debe reescribir la oferta que quedó asociada a una reserva ya aceptada: se conserva una instantánea versionada de los datos comerciales pertinentes.

El catálogo filtrará por ciudad/zona, operación de venta o alquiler, precio base, número de habitaciones y baños.

| Regla de oferta | Comportamiento acordado |
|---|---|
| Precio base | No incluye muebles opcionales. En alquiler, se expresa por mes; en venta, es el precio de venta del inmueble. |
| Muebles opcionales | La agencia define qué elementos ofrece y su precio. |
| Venta | El precio de cada elemento opcional es de un solo pago. |
| Alquiler | Es mensual: el total mensual resulta del precio base mensual más los recargos mensuales de los muebles opcionales seleccionados. |
| Cálculo de total | El servidor calcula y devuelve el desglose; el cliente no es autoridad de precios. |
| Ocultar muebles en 3D | Solo cambia la visualización. No elimina muebles de la oferta ni modifica el precio. |
| Reserva | Guarda una instantánea de inmueble, operación, oferta, elementos elegidos, precio y reglas vigentes. |

**RECOMENDADO:** mantener separadas las versiones de contenido visual y las versiones comerciales. La versión que una reserva fija debe poder reconstruirse aunque el agente cambie después fotografías, geometría, muebles o precio.

**ACORDADO:** la periodicidad del alquiler es mensual, tanto para el precio base como para los recargos opcionales.

**PENDIENTE:** impuestos, moneda, redondeo, descuentos, cargos obligatorios y vigencia de cotización. No deben inferirse de esta descripción.

## 4. Estados del inmueble y proceso de reserva

El proceso comercial es una reserva con depósito de prueba, no una compraventa ni un pago completo automatizado.

1. El cliente elige una oferta y conecta una wallet externa.
2. El cliente deposita una cantidad fija por inmueble, independiente del total de la oferta.
3. El contrato retiene el token de prueba mientras la reserva está pendiente.
4. Solo puede existir una reserva pendiente por inmueble; el estado reservado bloquea nuevas reservas.
5. Si el cliente cancela mientras está pendiente o la agencia rechaza, corresponde devolver el depósito.
6. Si la agencia no responde dentro de 24 horas, la reserva expira; la devolución requiere una transacción on-chain.
7. Si la agencia acepta, el inmueble queda reservado y la reserva conserva la instantánea acordada.
8. La venta o alquiler se marca como cerrado cuando ocurre la transacción legal externa, fuera de RoomForge.

### Lectura conceptual de estados

Esta tabla expresa transiciones de negocio descritas, no fija nombres de estados para API, base de datos o contrato.

| Situación | Regla conocida | Dato que aún no se debe inferir |
|---|---|---|
| Borrador de publicación | No aparece en el catálogo hasta aprobación de agencia. | Estados de revisión y reapertura tras cambios. |
| Publicado disponible | Puede recibir una reserva pendiente. | Ordenamiento o expiración de una publicación. |
| Reserva pendiente | Un único cliente; respuesta de agencia o vencimiento a las 24 horas. | Momento de inicio exacto del reloj y proceso si RPC falla. |
| Cancelado/rechazado/expirado | Debe devolverse depósito y liberarse el bloqueo comercial pendiente. | Finalidad del reembolso y reapertura exacta hasta confirmar cadena. |
| Aceptado/reservado | Bloquea nuevas reservas y conserva la instantánea comercial. | Tratamiento, destino y momento de liberación del depósito; mecanismo de desbloqueo excepcional. |
| Venta/alquiler cerrado | Se registra después de la transacción legal externa. | Evidencia documental requerida y comportamiento de catálogo posterior. |

**ACORDADO:** no se implementa cancelación automática de una reserva que ya fue aceptada. El depósito de la demo no equivale al precio total ni a la formalización legal.

**ACORDADO:** RoomForge no custodia claves privadas. El cliente usa wallet externa y firma las operaciones pertinentes.

**PENDIENTE:** se confirmó la retención del depósito en escrow mientras la reserva está pendiente; el tratamiento del depósito después de la aceptación no está confirmado. Transferirlo a la agencia al aceptar fue una recomendación, no un acuerdo. También quedan por definir las vías de recuperación ante errores, transacciones revertidas o reservas aceptadas que no culminen en cierre legal.

El token del depósito y la moneda nativa usada para pagar gas son conceptos distintos. No debe prometerse una transacción sin gas ni equipararse el token de prueba con dinero real.

### Integridad y límites de blockchain

**RECOMENDADO:** representar una oferta autorizada con firma, asociar su versión y monto al depósito, registrar eventos suficientes para auditar los cambios de estado y diseñar la integración para reintentos idempotentes y conciliación entre API, base de datos y cadena.

Los datos personales, fotos y modelos no deben guardarse on-chain. La cadena puede ayudar a verificar eventos y movimientos; no garantiza que una oferta sea verdadera, un contrato sea seguro o una transacción inmobiliaria legal se haya completado. Auditoría de contrato, control de errores de wallet y recuperación de transacciones son riesgos explícitos, no beneficios automáticos de usar blockchain.

**RECOMENDADO:** desarrollar primero en Hardhat local y validar una red de pruebas pública solo si el docente, la red, el RPC y el flujo de wallet lo permiten. **PENDIENTE:** confirmación del docente y selección de red. Hardhat/una testnet no se deben confundir con Floci, AWS ni con un mecanismo de custodia.

## 5. Captura espacial y recorrido 3D

### Geometría con ARCore

No se entregó un plano de muestra con cotas numéricas. El usuario no puede medir el salón y requiere una experiencia funcional; por ello, el enfoque propuesto es una guía de captura con ARCore para marcar esquinas y estimar dimensiones, con corrección manual posterior.

**RECOMENDADO:** permitir al agente marcar las esquinas del piso durante la captura, estimar las longitudes usando la escala y el tracking disponibles y presentar explícitamente qué valores son estimados. La altura podría inferirse desde techo/superficies detectadas cuando la señal sea utilizable; si no, se usará un valor supuesto de referencia, claramente etiquetado y editable, sin exigir que el usuario mida el salón.

No se promete exactitud instrumental, ni se asume que Depth API convierta directamente una foto en un plano fiable. El alineamiento entre ambientes será manual. Plantillas geométricas pueden servir para una demostración guiada, pero no deben etiquetarse como reconstrucción automática de una fotografía.

**ACORDADO:** las fotos forman parte del MVP; grabar y subir video solo se considerará si queda tiempo. Los fotogramas transitorios que ARCore use para tracking o estimación en vivo no equivalen a grabar o subir un video. Las fotos que se conserven o suban deberán respetar las decisiones de privacidad; su retención y sincronización exactas siguen pendientes.

El Galaxy S23 FE fue identificado como compatible con ARCore Depth API en la lista consultada. Esto acredita compatibilidad declarada, no precisión de medidas, rendimiento en este flujo ni funcionamiento integrado. Se necesita validación en el teléfono real.

Aunque no se exija al usuario medir el inmueble, la evaluación de precisión sí necesita una referencia independiente conocida para comparar estimaciones. Sin esa referencia se puede probar la interacción, pero no cuantificar error geométrico.

### Edición y navegación

**ACORDADO:** el cliente tendrá navegación 3D en primera persona con movimiento libre; no se propone limitar el producto a una secuencia de puntos de visita.

El editor y el visor usarán primitivas simples. **RECOMENDADO:** controles táctiles básicos, colisiones sencillas y pasos transitables por vanos/puertas, sin prometer animación de apertura, si se valida su costo. No VR ni salto en el MVP. Estos controles no se consideran comprometidos hasta validar el prototipo y la interacción.

La composición de varios ambientes, puertas de conexión y transformaciones requiere una convención espacial compartida. Las decisiones de escala, orientación, origen local y tolerancias siguen abiertas.

## 6. IA: alcance, opciones y riesgos

El usuario no tiene un dataset propio y acepta evaluar modelos preentrenados y recursos públicos en vez de entrenar desde cero. Esto no significa que un modelo seleccionado, sus pesos o su licencia hayan sido aprobados.

| Concepto | Significado para esta decisión |
|---|---|
| Biblioteca | Código/runtime que carga el modelo y ejecuta operaciones. |
| Arquitectura | Diseño de la red neuronal (por ejemplo, MobileNetV3 o YOLO). |
| Pesos preentrenados | Parámetros aprendidos que se descargan; no son lo mismo que el código ni que un dataset. |
| Dataset | Ejemplos usados para entrenar, evaluar o ajustar; cada conjunto tiene sus propios términos. |
| Inferencia | Aplicar pesos a una imagen para obtener predicciones. No entrena el modelo. |
| Fine-tuning | Ajustar pesos existentes con datos adicionales. No equivale a cambiar solo un umbral. |

### Candidatos, no selecciones

**RECOMENDADO para una primera evaluación:** Torchvision SSDLite320 MobileNetV3 Large con pesos COCO_V1. La documentación indica un archivo de pesos de aproximadamente 13,4 MB; eso no representa el tamaño total del runtime ni garantiza latencia, memoria o calidad en el teléfono.

Como alternativa puede estudiarse YOLO11n. La distribución de Ultralytics tiene obligaciones AGPL-3.0 y opción Enterprise; antes de incorporarla a un SaaS cerrado se requiere revisión de licencia. No asumir que una biblioteca con licencia abierta permite cualquier modalidad de distribución.

No se seleccionó, instaló, entrenó ni midió ninguno de los candidatos. Torchvision también advierte que se deben revisar los términos de pesos y datasets. El uso de COCO no sustituye datos representativos de interiores inmobiliarios; el cambio de escenas generales a interiores inmobiliarios introduce un posible domain shift que debe medirse.

### Capacidad realista de una detección

COCO incluye clases como silla, sofá, cama, mesa de comedor, televisor y refrigerador. No ofrece una clase estándar de puerta o ventana en la lista citada; un escritorio no es lo mismo que una mesa de comedor.

Un detector de objetos produce cajas 2D, clases y scores. No deduce por sí solo dimensiones reales, posición 3D, estructura de habitación ni precio. Un score no debe mostrarse como probabilidad calibrada. Varias fotos del mismo objeto no prueban que existan varios muebles físicos.

**RECOMENDADO:** presentar candidatos para confirmación humana, permitir descartarlos y ubicarlos manualmente en la escena, y definir que las cantidades/precios comerciales solo se basan en elementos confirmados por la agencia. Recortar el alcance antes de prometer detección de puertas, ventanas, superficies o mobiliario exhaustivo.

### Datos, prueba piloto e inferencia

Se propuso una prueba inicial con 20–40 fotos representativas. Es una evaluación exploratoria del flujo y de errores visibles, no un dataset suficiente para declarar calidad estadística, entrenar desde cero ni certificar desempeño. Requiere etiquetas o revisión manual de referencia, diversidad de iluminación/oclusiones y permiso para usar cada imagen.

Primero se debe comparar el modelo base con esa referencia, ajustar umbral y flujo de confirmación, después decidir si se reduce alcance o se justifica fine-tuning. Cambiar un threshold no es entrenar. No descargar un dataset grande antes de confirmar objetivo, términos y utilidad.

**RECOMENDADO para el piloto:** descargar una vez los pesos preentrenados seleccionados, ejecutar inferencia en la CPU de una PC propia y presentar sugerencias para confirmación humana. No depender de Gemini, ChatGPT ni de una API generativa paga; con pesos preentrenados no hace falta descargar un dataset completo para inferir. Esto define un flujo de evaluación local, no la ubicación final del modelo.

La propuesta original exige asistencia de IA offline en la app de captura. **RECOMENDADO:** evaluar primero inferencia en PC propia o AWS frente a ejecución en teléfono para comparar costo, conectividad, privacidad y latencia; esta recomendación no selecciona servidor ni proveedor. Ejecutar inferencia posteriormente en PC o AWS podría simplificar el paquete del teléfono, pero contradice o modifica el requisito offline. La ubicación del modelo (teléfono, PC propia o AWS), captura offline y sincronización posterior son una decisión abierta.

PyTorch es un candidato para una evaluación inicial. ONNX y ONNX Runtime Mobile son alternativas para empaquetado, sujetas a conversión, operadores, tamaño, memoria, latencia y compatibilidad real. No se afirma compatibilidad automática con Flutter ni equivalencia entre runtime móvil y servidor.

## 7. Arquitectura propuesta y alternativas

La arquitectura siguiente es una base para validar, no una aprobación de tecnología ni una afirmación sobre el estado del código existente.

| Área | Recomendación inicial | Alternativa/riesgo que se debe validar |
|---|---|---|
| API y dominio | Monolito modular FastAPI, PostgreSQL, SQLAlchemy y Alembic, en continuidad con la documentación. | Verificar el checkout y el estado real antes de reutilizar; dividir servicios solo ante una necesidad medida. |
| Tenancy | Base compartida con ownership explícito y aislamiento por agencia en cada operación. | Pruebas negativas de acceso cruzado; no confiar solo en filtros de interfaz. |
| Apps | Flutter para app cliente y app de captura Android, separadas por responsabilidades. | Confirmar versiones, plugins y plataformas efectivamente soportadas. |
| ARCore | Puente nativo Kotlin acotado, evaluando primero un plugin Flutter mantenido. | La integración nativa implica más código específico Android; el plugin puede limitar APIs o compatibilidad. |
| Panel | React + TypeScript + Vite, en continuidad con la propuesta histórica. | Evaluar flujo administrativo y esfuerzo de edición por separado. |
| Escena 3D | Three.js/TypeScript como visor/editor compartido; WebView móvil es una opción. | Probar memoria, rendimiento, controles, accesibilidad y seguridad de WebView; comparar con renderizado nativo. |
| Modelo de escena | JSON versionado con geometría de ambientes, transformaciones y referencias a muebles; JSONB puede alojarlo en PostgreSQL. | Versionado/migración del formato y límites de tamaño; no guardar binarios pesados como JSON. |
| Artefactos | S3 para fotos y binarios autorizados; GLB opcional de intercambio/exportación. | GLB no debe ser la única fuente de verdad de reglas comerciales o edición paramétrica. |
| Trabajo asíncrono | SQS y worker idempotente cuando haya procesamiento que lo requiera. | Cola estándar puede entregar un mensaje más de una vez; diseñar reintentos y estado durable. |
| Reconstrucción | Priorizar geometría paramétrica sencilla frente a Meshroom obligatorio en el MVP. | Mantener Meshroom como alternativa solo si el realismo resulta imprescindible y el spike lo justifica. |
| Red local | Docker Compose para servicios; Floci para probar S3/SQS localmente. | Floci no equivale a AWS en seguridad, disponibilidad ni todos los comportamientos. |
| AWS demo | Probar temprano despliegue pequeño con datos no sensibles, persistencia y respaldo. | EC2 + Compose + PostgreSQL persistente + S3/SQS reduce piezas, pero concentra fallas y exige probar restore. |
| Hosting histórico | ECS/Fargate y RDS aparecen en infraestructura anterior. | Mayor separación administrada, pero costo/operación no validados; no asumir créditos o gratuidad. |
| CI | GitHub Actions es una recomendación para checks reproducibles. | Elegir runners/versiones tras inspección del repositorio; no se crean pipelines aquí. |

**RECOMENDADO:** utilizar un monolito modular antes que microservicios, Kubernetes, Kafka o Redis sin necesidad probada. Eso reduce configuración, despliegue y mantenimiento para dos desarrolladores; no elimina la necesidad de definir límites de dominio y controles de acceso.

La captura AR y la interacción primaria corren en el teléfono: Docker no sustituye una app Android ejecutada en dispositivo real. La arquitectura de nube tampoco debe convertir captura sin conexión en requisito de conectividad permanente.

### Costos y operación

Se informó una disponibilidad de USD 100 en créditos AWS, aún no validada en cuenta, elegibilidad, vencimiento, región ni servicios. No debe presupuestarse como crédito confirmado ni confundirse con costo cero.

**RECOMENDADO:** validar crédito y región, configurar alertas y presupuestos operativos y limitar recursos de prueba. Las alertas no siempre son límites duros; revisar la facturación y detener servicios de demostración cuando corresponda. No se afirma una cifra de costo.

TLS, secretos fuera del repositorio, roles IAM de privilegio mínimo, backups y una prueba de restauración son controles recomendados. Floci facilita desarrollo local, pero no demuestra estos controles ni paridad completa con AWS.

## 8. Criterios de calidad y evidencia requerida

Estos siete criterios son la rúbrica indicada por el docente para organizar la conversación; no se presentan como certificación ISO ni como resultados ya logrados.

| Criterio | Requisito verificable propuesto | Evidencia antes de declarar cumplimiento |
|---|---|---|
| Correcto | Reglas de reserva, publicación, precios y permisos coherentes con los estados acordados. | Pruebas unitarias e integradas de reglas, snapshots y estados límite; revisión de transacciones on-chain. |
| Eficiente | Captura, editor y visor utilizables en los dispositivos objetivo. | Medición reproducible de latencia, memoria y fluidez en dispositivos reales; fijar umbrales después de baseline. |
| Fiable | Reintentos, expiración, rechazo y devolución toleran fallos y duplicados. | Pruebas de idempotencia, entrega repetida de SQS, RPC fallido, reinicio y restauración de backup. |
| Fácil de usar | Agente puede capturar/corregir/publicar; cliente puede navegar y reservar con wallet. | Pruebas de tareas con usuarios, errores observados y revisión de controles táctiles. |
| Fácil de mantener | Formato de escena versionado, responsabilidades modulares y reglas explícitas. | Revisión de migraciones, contratos API, legibilidad y reproducción de entorno. |
| Seguridad e integridad | Aislamiento tenant, autorización de oferta, ausencia de custodia y control de secretos. | Casos negativos entre agencias, revisión de permisos, pruebas del contrato y manejo seguro de wallet. |
| Portabilidad | Entorno local repetible y despliegue demostrable en AWS. | Smoke test local con Docker/Floci y despliegue/reinicio/restore en AWS; registrar diferencias. |

**PENDIENTE:** establecer umbrales de medida, FPS, tiempo de respuesta, memoria, disponibilidad, recuperación, retención y presupuesto. Los valores de documentos previos no quedan confirmados automáticamente por esta redefinición. No hay resultados de PASS/FAIL en este documento.

## 9. Ruta de implementación recomendada

El plazo reportado es un mes con dos desarrolladores. Es una restricción para planificar, no evidencia de que captura, 3D, multi-tenancy, blockchain y nube estén completos o sean alcanzables en ese plazo. Recomendar empezar por riesgos que puedan invalidar el diseño antes de construir todo el producto.

### Etapa A — validaciones técnicas cortas

1. **AR/geometría:** prototipo de esquinas guiadas en el S23 FE, registro de escala, edición manual y altura estimada/supuesta. Comparar con dimensiones de referencia independientes; registrar desviaciones y límites.
2. **Visor:** escena paramétrica con varias habitaciones conectadas, movimiento libre en primera persona y controles táctiles. Comparar Three.js en WebView con alternativa nativa sobre el teléfono objetivo.
3. **IA:** evaluación licenciada de uno o dos candidatos sobre fotos con referencia manual. Medir errores prácticos y costo de inferencia; probar primero candidatos sin convertirlo en una promesa de automatización.
4. **Escrow:** flujo mínimo local con wallet externa: depósito fijo, cancelación/rechazo, timeout, aceptación, evento duplicado y RPC/transacción fallidos. Confirmar el estado del dinero después de aceptar antes de fijar la lógica final.
5. **AWS y presupuesto:** validar cuenta/créditos/región, desplegar un servicio pequeño, comprobar persistencia, acceso y restauración, y estimar consumo observado.

### Etapa B — corte vertical integrado

Tras decidir los resultados de los spikes, construir una sola trayectoria demostrable: administrador crea agencia, agente prepara y envía un inmueble de un piso, administrador aprueba, cliente filtra y recorre, y cliente crea una reserva de prueba que se resuelve en los estados confirmados.

Cada superficie debe probar autorización y fronteras tenant. La geometría puede ser corregida manualmente; detección automática, video, fotorrealismo, reconstrucción Meshroom, pagos completos y suscripciones no son dependencias de ese corte.

### Etapa C — robustez y demostración

Añadir solo funcionalidades que quepan tras revisar capacidad real: reglas de alquiler y opcionales, recuperación/idempotencia, pruebas de contrato, controles de seguridad, despliegue AWS, observabilidad suficiente y ensayo de extremo a extremo.

AWS es requisito para la demostración final, pero no conviene dejar el primer despliegue para el último día. Hacer pruebas tempranas no significa pagar infraestructura completa durante todo el desarrollo.

El orden y profundidad pueden cambiar a la luz de los resultados. No se crea aquí planificación por semanas, asignación de responsables, criterios de aceptación numéricos, backlog ni artefactos SDD.

## 10. Alternativas evaluadas y razones

| Decisión de diseño | Alternativa considerada | Razón para preferir la opción recomendada (sujeta a prueba) |
|---|---|---|
| Geometría paramétrica sencilla | Reconstrucción completa fotogramétrica como requisito inicial. | El alcance pide modelos simples editables y reduce dependencia de GPU, tiempo de worker, malla/texturas y fallos de reconstrucción. |
| Detección preentrenada asistiva | Entrenar desde cero o prometer reconocimiento integral de interiores. | No hay dataset propio ni presupuesto de anotación; pesos preentrenados son un punto de partida medible, no evidencia de calidad del dominio. |
| Monolito modular | Microservicios desde el inicio. | Dos desarrolladores y un mes favorecen menos despliegues y menor carga operativa. |
| Escena versionada + GLB exportable | GLB como única fuente del contenido comercial y paramétrico. | Una malla no representa por sí sola estados, precios, reglas o edición estructurada. |
| Base compartida con aislamiento explícito | Una base de datos por agencia o tenancy solo cosmética. | Menos componentes iniciales que una instancia por agencia, sin relajar autorización ni pruebas de separación. |
| WebView Three.js a validar | Implementar de entrada dos visores nativos distintos. | Potencial reutilización entre web y móvil; memoria/rendimiento/control táctil pueden invalidar la opción y requieren spike. |
| EC2 + Compose para primera demo, como hipótesis | ECS/Fargate + RDS según diseño histórico. | Puede reducir la cantidad de piezas iniciales, pero concentra fallas y carga tareas de operación; no hay conclusión de costo hasta medir. |
| Wallet externa | Custodia de claves o pago de reserva con dinero real. | Custodia amplía riesgo y responsabilidad; alcance acordado usa token de prueba y no custodia claves. |

Ninguna alternativa de la tabla se considera descartada para siempre. La recomendación sirve para fijar el orden de validación y hacer visibles los costos de decisión.

## 11. Decisiones abiertas que impiden cerrar la especificación

| Tema | Situación actual | Qué hace falta para resolverlo |
|---|---|---|
| Inferencia IA local o remota | La propuesta original exige offline; ubicación en PC/AWS se sugirió, pero no se aprobó. | Decisión del usuario/docente tras estimar paquete móvil, privacidad, red y latencia. |
| Modelo, pesos y licencia | SSDLite y YOLO11n son candidatos ilustrativos. | Revisión legal/técnica y comparación con datos autorizados. |
| Editor y visor | Three.js en WebView es recomendación. | Resultado del prototipo de interacción/performance y decisión de plataforma. |
| Precisión y dimensiones | No hay cotas del aula ni tolerancia acordada. | Evaluación con referencia independiente y umbrales elegidos por el equipo/docente. |
| Depósito después de aceptación | Se acordó retención, no el destinatario/tiempo de liberación. | Confirmar regla de negocio, devoluciones y quién puede resolver excepciones. |
| Cancelación tras aceptación | No se automatiza en el MVP. | Definir manualmente qué significa cancelar y cómo se desbloquea el inmueble ante contingencia, si aplica. |
| Red de pruebas | Hardhat local es opción de desarrollo; testnet es recomendación. | Aprobación docente, RPC/red, wallet y experiencia de gas. |
| Token y parámetros | Depósito fijo por inmueble, pero monto, decimales, titularidad y despliegue no constan aquí. | Definición explícita; no inventar valores. |
| Moneda, región, créditos AWS | USD 100 fue informado, no validado. | Consultar cuenta/región/vencimiento/cobertura y medir consumo. |
| Plataformas y versiones | Flutter/React y Android se describen; versiones exactas no se seleccionan. | Inspección de repositorios y compatibilidad de dependencias existente. |
| Alcance del mes | Dos desarrolladores y un mes es el límite reportado. | Estimación basada en spikes y recorte explícito del MVP; no prometer el alcance total. |
| Umbrales de calidad | No están definidos aquí ni medidos. | Acordar targets una vez obtenida una línea base. |

## 12. Preparación para implementar

**Sí:** existe suficiente dirección para iniciar validaciones técnicas por etapas. El primer trabajo útil es probar AR/geometría, visor móvil, evaluación de IA, escrow local y despliegue AWS mínimo antes de apostar por la solución completa.

**No:** todavía no se puede afirmar viabilidad completa, calidad de medidas, compatibilidad de toda la pila, seguridad del contrato, suficiencia de créditos ni entrega integral en un mes. Esas son preguntas que los spikes deben responder.

La recomendación es **sí iniciar implementación incremental**, empezando por los spikes técnicos descritos; no equivale a autorización para saltar esas validaciones y construir el producto completo. Este documento no ejecuta cambios de producto ni crea artefactos OpenSpec/SDD. Antes del corte vertical, deben seleccionarse decisiones, acordarse criterios de aceptación y reconciliarse los requisitos nuevos con la documentación y backlog canónicos.

## 13. Fuentes técnicas de referencia

Las fuentes siguientes sustentan afirmaciones específicas sobre plataformas y candidatos; no sustituyen las pruebas en RoomForge ni la revisión de licencias. Se listan sin fecha de consulta para no inventarla.

1. Google ARCore, dispositivos compatibles: <https://developers.google.com/ar/devices>.
2. Google ARCore, guía de hit-test en Java: <https://developers.google.com/ar/develop/java/hit-test/developer-guide>.
3. Flutter, platform channels: <https://docs.flutter.dev/platform-integration/platform-channels>.
4. Torchvision, SSDLite320 MobileNetV3 Large y pesos COCO_V1: <https://docs.pytorch.org/vision/stable/models/generated/torchvision.models.detection.ssdlite320_mobilenet_v3_large.html>.
5. Torchvision, modelos y notas sobre pesos/datasets: <https://docs.pytorch.org/vision/stable/models.html>.
6. Ultralytics, dataset COCO: <https://docs.ultralytics.com/datasets/detect/coco/>.
7. Ultralytics, YOLO11: <https://docs.ultralytics.com/models/yolo11/>.
8. Ultralytics, licencia: <https://www.ultralytics.com/license>.
9. ONNX Runtime, despliegue móvil: <https://onnxruntime.ai/docs/tutorials/mobile/>.
10. Amazon SQS, colas estándar y entrega al menos una vez: <https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/standard-queues-at-least-once-delivery.html>.
11. Ethereum.org, redes de desarrollo y pruebas: <https://ethereum.org/en/developers/docs/networks/>.
12. Floci, emulación local de servicios AWS: <https://github.com/floci-io/floci>.

## 14. Estado de evidencia y límites

- El estado inicial del repositorio ya contenía cambios en submódulos, OpenSpec, archivos de infraestructura y otros elementos. Este trabajo no los modifica ni atribuye su autoría.
- Una exploración previa reportó que no verificó código/manifiestos utilizables en superficies examinadas; esto no prueba ausencia de código ni invalida afirmaciones históricas de implementación. El estado del checkout sigue sin reconciliarse.
- El hardware comunicado para la PC es Intel Core 5 120U (10 núcleos/12 hilos), 15,65 GiB de RAM e Intel Graphics, con Windows 11 Home x64; el espacio libre reportado fue aproximadamente 32,86 GiB en C: y 28,31 GiB en D: al observarlo. No es un benchmark y el espacio disponible puede cambiar.
- El teléfono informado es Samsung Galaxy S23 FE; su compatibilidad ARCore citada no acredita precisión ni desempeño de la aplicación propuesta.
- No se ejecutaron pruebas de RoomForge, modelos IA, ARCore, contratos, AWS ni costos como parte de este documento. No se afirma ningún criterio aprobado.
- Las referencias a GAPs, PBs, HUs y decisiones previas continúan sujetas a su fuente histórica. Este documento no los cierra, reenumera ni declara implementados.
