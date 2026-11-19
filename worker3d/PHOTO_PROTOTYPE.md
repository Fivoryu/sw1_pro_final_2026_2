# Prototipo local: plano desde fotografías

Este experimento independiente utiliza PyCOLMAP y la geometría proporcional existente; no modifica la aplicación ni la API. Requiere Python y el runtime PyCOLMAP del piloto de reconstrucción (`worker3d/README.md`). No instala dependencias automáticamente.

1. Guardá fotos JPG/JPEG o PNG de **una sola habitación** en una carpeta sin subcarpetas ni otros archivos. Ordenalas por nombre lexicográfico con ceros, por ejemplo `0001.jpg`, `0002.jpg`. Usá la misma cámara, orientación y resolución para todas; el estimador comparte una calibración.
2. Desde la raíz, ejecutá:

   ```bash
   python worker3d/reconstruct_photos.py ruta/fotos --work-dir ruta/trabajo-fotos-nueva
   ```

   El directorio de trabajo debe no existir y estar separado de la carpeta de fotos. Se crea y conserva con la base y los archivos intermedios de SfM; pueden contener información de las imágenes. La salida JSON va a stdout; un rechazo explicativo va a stderr y devuelve código 1.

3. `contour` contiene puntos (x, z) en orden, en **unidades arbitrarias**, y se cierra entre el último y el primero. No son metros, no sirven para calcular superficies reales ni acreditan precisión. Puede incluir paredes inferidas: revisar visualmente el resultado.

## Captura y límites

Caminá por la habitación y fotografiá paredes y esquinas desde posiciones distintas, con amplio solapamiento entre imágenes consecutivas. Desplazate lateralmente entre vistas y mantené simultáneamente un detalle cercano y el fondo visibles en las vistas solapadas. Mantené la cámara vertical y evitá fotos borrosas, iluminación cambiante, superficies sin textura, reflejos y objetos móviles. No basta girar la cámara desde un mismo punto: hace falta paralaje. Las fotos deben cubrir las paredes, no solo el mobiliario o el suelo.

La vertical se aproxima a partir de la orientación de las cámaras, sin sensores: fotos inclinadas pueden producir un plano erróneo. No hay escala física, ARCore, medidas, referencia métrica ni garantía de reconstrucción; el resultado no fue validado contra una habitación real. Si no se obtiene ningún modelo, aparecen modelos desconectados o se registran pocas fotos, el rechazo identifica el caso y, cuando corresponde, informa los conteos observados; repetí la captura siguiendo la indicación anterior. Si no se puede cerrar un contorno, repetí la captura con mayor cobertura de paredes y solapamiento. El prototipo no genera un video ni simula datos de sensores.
