# Especificación del corte de corrección

- F07-01/02/15/16/17/21/22: borradores sin escala en unidades arbitrarias; referencia dentro del soporte observado; distorsión radial coherente; procedencia SfM explícita. API impide aceptar/guardar/publicar sin escala, referencia confirmada, reloj fiable y conexión entre piezas.
- F07-05/13/25/28: comprobar bytes, CRC y manifiesto; snapshot remoto separado y checksum persistente. No confirmar entrega ni eliminar ZIP local sin `uploadVerified` y cola durable. Identidades de claim/manifiesto deben coincidir.
- F07-04/11/12/14/23: readiness y errores recuperables; contraste de PTS/callbacks, referencia sobre cuadro codificado, conservar originales ante interrupciones/errores. No afirmar sincronización física solo por pruebas JVM.
- F07-06/07/08/26/27: renovación con token vigente, descarga acotada, timeout nativo, presupuesto de hilos/cuadros, resultado persistente antes de completar y runtime reproducible.
- F07-09/10: retorno de red validada, renovación de sesión offline antes de enviar, single-flight y persistencia serializada/atómica, sin regresión de etapas y con recuperación de backup/journal.
- Se admiten paquetes 1 y 2 y escenas históricas; los nuevos metadatos no convierten datos antiguos en mediciones verificadas.

Extensión autorizada por la auditoría independiente R01–R12: segundo plano no descarta raw;
recuperación durable por propietario; purga terminal sin reactivación; publicación sin consumir
intentos; aceptación vinculada a escena persistida y revisión; procedencia capturada preservada;
validación ZIP fuera de locks prolongados; recuperación de backup estructural; conciliación
histórica comprobada; caché privada acotada; reintento de aceptación sin PUT adicional.
El offset absoluto MP4/IMU requiere QA física y no se certifica con tiempos relativos.

## Escenarios de integración con Trevor

- Un plano `scale.mode: proportional` se conserva como borrador `unit: arbitrary`; no sirve para medidas, superficies ni precios por área. Un documento antiguo proporcional que declara metros se normaliza al validar o responder una captura, sin reescribir evidencia durante una lectura.
- El factor nominal proporcional nunca satisface el requisito de referencia real. Se conservan los controles de reloj, gravedad, conectividad, confirmación y autorización para aplicar una captura métrica.
- Un rectángulo inconsistente o una referencia sin pose/soporte no obtiene escala mediante un fallback silencioso. Componentes con evidencia distinta no mezclan unidades.
- El eje compartido y las aberturas de Trevor conviven con selección de contornos por evidencia, advertencias de cámaras y diagnósticos de referencia. La detección de puertas puede faltar sin invalidar el respaldo manual.
- Un acierto en caché evita SfM pero nunca omite la validación de tiempos MP4. Los diagnósticos nativos se conservan y las condiciones de aceptación se recalculan.
