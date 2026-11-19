# Diseño mínimo aplicado

Se amplían estructuras existentes, sin nuevos servicios de negocio. La revisión `0036_capture_integrity`, hija de `0035_merge_f07_heads`, añade solo checksum y manifiesto nullable a `listing_capture`: necesarios para conservar identidad/integridad entre subida, reinicio y claim sin reinterpretar registros históricos.

Los metadatos de medida viven en el JSON de escena. `arbitrary` es exclusivo del borrador de captura; las superficies métricas de catálogo lo rechazan en el servidor. Se conserva el esquema de salida 2.0, con extensión aditiva de procedencia.

El snapshot verificado no comparte la clave de la URL PUT. El worker verifica hash/identidad, renueva su lease mientras procesa y conserva resultados por job/checksum antes de reportarlos. El SfM se aísla en subprocess para terminarlo por timeout; se limita a cuatro hilos, 300 cuadros y matching temporal para secuencias mayores de veinte imágenes.

La cola existente se serializa por directorio de propietario, mantiene etapas monótonas y un backup válido. Un journal nativo por propietario permite recuperar un ZIP cuyo resultado aún no se encoló. La referencia se marca después de finalizar, sobre el primer cuadro codificado, sin inferir su imagen desde TextureView.

Las tolerancias operativas y de PTS no son exactitud medida. No se da por verificado Docker/Linux, PostgreSQL ni un teléfono por haber pasado pruebas locales.

## Decisiones de integración, 18/11/2026

`_Piece.factor` conserva exclusivamente evidencia métrica; `display_factor` normaliza la vista
proporcional. La salida declara simultáneamente `unit`, `scale.mode` y `measurement`.
La política métrica central rechaza proporciones aun si un documento histórico declaraba metros.
La API conserva capturas privadas, separadas de la escena publicable.

La selección local evalúa candidatos por componente antes de ensamblar. Los segmentos de un mismo
componente comparten eje; sus habitaciones/aberturas usan el mismo grupo de paredes, sin soldar
componentes desconectados. La caché SfM guarda `(modelos, diagnósticos)` con versión de adaptador
y presupuesto de muestreo. Validación temporal, gravedad, referencia y ensamblado quedan fuera
de esa caché. La caché privada de resultados mantiene sus límites y controles anteriores.

PostgreSQL aislado y la imagen Linux independiente se verificaron en esta integración;
los resultados y límites están en el informe. Los teléfonos y la aceptación física siguen pendientes.
