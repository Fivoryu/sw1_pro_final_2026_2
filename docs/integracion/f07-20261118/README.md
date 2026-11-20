# Integración F07 — Trevor e implementación local

**Fecha:** 18/11/2026, Bolivia. **Resultado:** integración técnica y regresión verificadas; no constituye aceptación física de F07 ni cierre de #63/#71. No se crearon commits, push ni PR.

Este informe se complementa con [verificación y límites](verificacion.md), [lista exacta de archivos del PR](archivos-pr.md) y [fuentes y trazabilidad documental](plan-documentacion.md).

## Fuentes y preservación

- Fuente local de solo lectura: `D:\2-2026\SW1\Proyecto Final\roomforge-f07-video-qa`, HEAD separado `95a730e0318e435eb62dde867e7ac527a55bfc67`.
- Base remota del nuevo worktree: `46b092a312a360b690ba6a0ff7b5a53e516d3a4b`, `origin/feat/f07-video-capture`: 26 commits y 41 rutas desde la base local.
- Destino exclusivo de escritura: `roomforge-f07-integracion-20261118-201958`, rama `integracion/f07-20261118-201958`.
- Se inventariaron 59 archivos locales versionados modificados y 33 archivos nuevos de producción, pruebas, infraestructura y OpenSpec. Trece rutas versionadas también cambiaron en Trevor; siete necesitaron resolución textual después de normalizar los finales de línea para comparar.
- Quedaron fuera 918 archivos sin seguimiento del original: evidencia, capturas, informes de auditoría y otros artefactos ajenos al código incorporado. No se importaron paquetes de video, secretos ni archivos privados. La regla `/F07_*` excluye los artefactos de raíz del worktree nuevo, incluidos logs, inventario, temporales y herramientas de integración.
- La comprobación posterior encontró el mismo HEAD, el mismo estado de Git y los mismos SHA-256 en los 92 archivos locales inventariados. No se ejecutaron reset, clean, stash, commit, push ni cambios de rama en el original. El binario de Enterprise Architect no se tocó.

## Cambios combinados

| Superficie | Resultado de la integración |
|---|---|
| Captura Android/Flutter | Se preservaron la guía híbrida, progreso y muestreo visual, referencia sobre un cuadro decodificado, confirmación de dimensiones, comparación MP4/Camera2, recuperación al interrumpirse la actividad y journal de paquetes. Se conservó el texto proporcional de Trevor junto con la asignación de propietario local. |
| Cola y recuperación móvil | Se conservaron eventos de conectividad, serialización por propietario, backup, etapas monótonas, conciliación del estado remoto, reintentos e idempotencia. La copia local solo se libera con recibo de subida verificada. |
| Backend | Integridad, identidad y CRC del ZIP, snapshot remoto verificado, checksum/manifiesto persistentes, renovación de lease y fencing por token. Se preservaron ETags y procedencia de captura al guardar y aceptar. |
| Worker | Se combinaron selección de componentes/contornos por evidencia y diagnósticos privados de SfM con normalización proporcional, eje dominante, regularización, paredes compartidas y colocación de aberturas de Trevor. |
| Aberturas | OWLv2 continúa opcional y apagado por defecto. Una dependencia o modelo no disponible produce advertencia y mantiene el borrador sin detecciones; se conserva la corrección manual. El reconocimiento no acredita escala, conectividad ni precisión. |
| Cachés | Se conserva la caché de etapas de Trevor y la caché privada de resultados/reintentos local. La caché SfM incluye diagnósticos nativos y versión del adaptador; cambiar sensores o umbrales geométricos no exige repetir SfM. Cambiar el presupuesto de cuadros sí invalida esa etapa. La verificación de tiempos MP4 se ejecuta aun con caché. |
| Panel | Inspección provisional aislada, limpieza al cambiar de inmueble/autorización y bloqueo de aplicación no métrica. Se mantienen revisión de aberturas estimadas, alturas relativas sin rótulos en metros, revisión de muebles y reintento de aceptación sin repetir PUT. |

## Conflictos resueltos por contrato

1. **Unidad y escala.** `scale.mode` de Trevor y `measurement` local coexisten. Los planos proporcionales nuevos usan `unit: "arbitrary"`; el factor nominal de visualización es independiente del factor métrico. Un documento proporcional antiguo que declaraba metros se normaliza al validar o responder una captura, sin reescribir evidencia histórica durante una lectura.
2. **Aceptación métrica.** El factor nominal nunca acredita referencia real. Para aplicar una reconstrucción métrica se conservan escala por referencia, reloj verificado, gravedad utilizable, geometría conectada, confirmación de dimensiones, pertenencia a agencia/inmueble y autorización. Una confirmación de altura o abertura no convierte un plano proporcional en métrico. Guardar, aceptar, publicar y consultar públicamente mantienen controles independientes.
3. **Referencia.** Se conserva la verificación local sobre soporte finito y el diagnóstico `FRAME_NOT_REGISTERED`. Un rectángulo inconsistente no recupera silenciosamente una escala por dos puntos. Si solo parte de los componentes tiene referencia, la salida completa queda proporcional para evitar mezclar escalas.
4. **Geometría.** Cada componente usa el eje común de Trevor, pero se evalúan sus candidatos antes de escoger por evidencia; no vuelve la regla de quedarse con la primera pieza. Las paredes compartidas se agrupan por componente para no unir piezas desconectadas artificialmente. Se mantienen avisos de paredes inferidas y de falta de cámaras dentro del contorno seleccionado.
5. **Caché y diagnóstico.** Extraer/estimar se ejecuta de forma diferida; la caché almacena modelos y datos de diagnóstico. La validación de tiempos no se salta y los metadatos de aceptación se calculan nuevamente. Las advertencias nunca se convierten en evidencia de aceptación física.
6. **Pruebas.** Se actualizaron expectativas del tamaño nominal proporcional conservando pruebas de invariancia de escala. Los dobles de contorno admiten el eje compartido. Una prueba F08 que dependía de que Pillow no hubiera sido importado por otras pruebas ahora demuestra la ausencia de esa dependencia en un proceso aislado; no se modificó el producto F08.

Los siete archivos con conflictos textuales fueron `backend/app/modules/catalog/schemas.py`, `panel/staff-shell/src/application/sceneContract.ts`, `CaptureDraftPanel.tsx`, su prueba, `worker3d/reconstruct_video.py`, `worker3d/reconstruction_worker.py` y `worker3d/tests/test_reconstruct_video.py`. Las rutas completas figuran en el manifiesto del PR.

## Compatibilidad y persistencia

- F06 conserva versión de escena `2.0`, coordenadas métricas para escena del inmueble y visor público, ETags y edición manual. Los borradores proporcionales se conservan como capturas privadas inspeccionables, sin habilitar cálculo de superficies, precios por área o publicación. Los precios comerciales existentes no se derivan de coordenadas proporcionales.
- El contrato de paquete v1 sigue despachándose al reconstructor existente; v2 utiliza video/sensores. Se conserva ARCore heredado y el respaldo manual/plano. Los campos nuevos son aditivos; los documentos métricos manuales históricos siguen válidos.
- F08 conserva sugerencias, revisión humana e inventario comercial. Las cajas de video declaran `sfm_estimated`; `depth` y `manual` no cambian. La IA de aberturas no confirma muebles ni modifica precios o contratos.
- La migración aditiva `0036_capture_integrity` depende de `0035_merge_f07_heads`, con dos columnas nullable. Se verificó una única cabeza, subida completa en PostgreSQL 16 y rollback/re-upgrade de `0036` preservando una fila histórica. No se migró ninguna base existente del equipo.

## Pendientes y alcance de entrega

La aceptación física continúa pendiente: video real controlado, offset absoluto MP4/Camera2/IMU, rotaciones y pruebas S23 FE/A53; tres habitaciones medidas independientemente; conectividad y referencia plausibles; error y tolerancias acordados; desempeño con videos de 30/90/300 segundos y calidad de aberturas reales. No se sustituyó esa evidencia con pruebas sintéticas, logs históricos, un modelo cargado o una imagen Docker construida.

La exclusión comercial de muebles y el resto del alcance pendiente de #63 no forman parte de esta integración. No se eliminó ARCore ni se cerró #71. La caché de etapas sigue siendo opcional para un piloto privado y no debe activarse como almacenamiento permanente de capturas sin una política de retención adecuada.

El resultado queda sin stage ni commit para revisión humana. El destino propuesto de un eventual PR es `feat/f07-video-capture`; no se creó. Los archivos heredados de Trevor ya están en esa base y se enumeran por separado del delta de integración.
