# Verificación de la integración F07

Resultados ejecutados el 18/11/2026 sobre el worktree de integración. Las pruebas sintéticas y los controles nativos no acreditan exactitud ni aceptación física.

## Resultados

| Comprobación | Resultado observado |
|---|---|
| Backend antes de integrar | 1139 passed, 16 skipped. La primera corrida adicional tuvo 22 errores por permisos del temporal de Windows; se repitió con temporal aislado. |
| Backend completo integrado | 1185 passed, 17 skipped. |
| Integración nueva worker → API → persistencia | Seis casos aprobados: salida proporcional, métrica, reloj desconocido, referencia no confirmada y dos variantes históricas proporcionales. Incluidos en la suite completa. |
| Worker completo, FFmpeg nativo habilitado | 450 passed, 1 skipped. La omitida requiere fotografías externas para SfM; no se importaron capturas del original. |
| Último ajuste de diagnóstico de caché | 22 pruebas enfocadas de caché/selección de componentes aprobadas; conserva tiempos nativos y distingue reutilización de cálculo nuevo. Ruff y Pyright limpios después del ajuste. |
| FFmpeg nativo aislado | Tres casos aprobados: selección exacta de cuadros, tiempos MP4 y selección de conjuntos de 145/300 índices; incluidos en la suite del worker anterior. |
| Readiness nativo Windows | Encoder/decoder FFmpeg y extracción/emparejamiento PyCOLMAP 4.2.1 CPU aprobados. |
| Panel | 309 pruebas Vitest aprobadas; TypeScript sin errores; build Vite aprobado. Advertencia de tamaño de bundle, sin fallo. |
| App de captura | 726 pruebas Flutter aprobadas; Analyze sin incidencias. SDK utilizado: Flutter 3.41.8. |
| Android | `:app:testDebugUnitTest` aprobado: 307 pruebas JVM, cero fallos, errores u omisiones. Compilación Kotlin/Java incluida. Advertencias de APIs Android obsoletas, sin fallo. |
| F06 cliente | 21 pruebas JavaScript de geometría del visor aprobadas. |
| Backend Ruff/Pyright | Ruff completo limpio; Pyright completo sin errores ni advertencias de diagnóstico. Se indicó explícitamente el intérprete instalado; el CLI avisa que este worktree no tiene `.venv` propia. |
| Worker Ruff/Pyright | Ruff en archivos Python modificados/nuevos con las reglas del backend limpio; Pyright sobre reconstructor, consumidor y smoke sin errores ni advertencias. La configuración local de verificación incluye dependencias nativas instaladas. |
| Migraciones PostgreSQL 16 | Cadena completa hasta `0036_capture_integrity`, una cabeza; rollback a `0035` y re-upgrade aprobados. Columnas nuevas nullable y fila histórica conservada. |
| Imagen Linux | Construcción separada `roomforge-f07-integration:20261118` con smoke nativo CPU durante el build, sin reemplazar servicios existentes. |
| Preservación | HEAD y estado Git originales iguales; SHA-256 iguales en los 92 archivos locales de código/artefactos de cambio inventariados. |

## Regresiones y ajustes

- La fusión inicial trató como conflictos finales de línea distintos. Se normalizaron solo las entradas de comparación; no se editó el original. Quedaron siete conflictos reales que se resolvieron por comportamiento.
- Las primeras pruebas detectaron expectativas anteriores sobre el tamaño nominal del plano y dobles de contorno sin el argumento de eje dominante. Se conservaron y adaptaron las pruebas de invariancia y de clasificación de fallos.
- La persistencia proporcional que antes admitía metros ahora recibe `422` al intentar guardarse como escena métrica. Se cubren además lectura histórica de captura, publicación y consulta pública.
- Se probaron explícitamente reutilización de SfM con sus diagnósticos y rechazo de tiempos inválidos aun con caché. Cambiar umbrales geométricos conserva la etapa; cambiar el presupuesto de muestreo la recalcula.
- Al habilitar pruebas FFmpeg, una prueba de la hoja F08 falló por depender de `sys.modules` compartido. Se corrigió para ejecutar el CLI en un proceso donde Pillow está bloqueado, manteniendo la garantía original de dependencia opcional.
- Gradle necesitó plugins en la misma unidad que el proyecto. Se copiaron seis dependencias a `F07_android_plugins/`, carpeta local ignorada, y se ajustó únicamente el archivo generado de plugins. La ejecución amplia de pruebas de terceros requería Mockito no cacheado; se verificó la tarea de pruebas de la app, que sí completó sus 307 casos.

## Comandos reproducibles

Ejecutar con dependencias disponibles y temporales nuevos dentro del worktree. No apuntar pruebas a las bases o servicios de evidencia originales.

```powershell
# Desde backend/, usando el Python del entorno de desarrollo instalado:
python -m pytest tests -q --basetemp=../F07_tmp_backend_nueva_corrida
python -m ruff check app tests --no-cache
python -m pyright app tests --pythonpath <python-del-entorno>
python -m alembic heads

# Desde la raíz; ROOMFORGE_FFMPEG apunta al ejecutable nativo instalado:
python -m pytest worker3d/tests -q -p no:cacheprovider --basetemp=F07_tmp_worker_nueva_corrida
python worker3d/runtime_smoke.py
node --test apps/cliente_mobile/test_js/viewer_geometry.test.mjs

# Desde panel/staff-shell/:
npm test
npm run build

# Desde apps/captura_mobile/:
flutter test
flutter analyze --no-pub
# Desde android/, con Gradle 8.14 y Java 17+ instalados:
gradle :app:testDebugUnitTest --offline --no-daemon

# Imagen independiente, desde la raíz:
docker build -f infra/docker/inference/Dockerfile.reconstruction -t roomforge-f07-integration:20261118 .
```

Los logs detallados y el inventario SHA-256 quedan en archivos locales `F07_*.log` / `F07_integration_inventory.json`, excluidos de Git. Los logs de Docker usan UTC; las fechas de este informe usan Bolivia. No se copiaron logs o paquetes privados de la fuente al PR.

El PostgreSQL desechable `roomforge-f07-integration-20261118` se detuvo tras comprobar la migración
y se eliminó automáticamente por su opción `--rm`. La imagen de integración queda disponible;
los cuatro contenedores originales siguen presentes y no se reiniciaron ni reemplazaron.

## Bloqueantes físicos y límites

1. Medir el offset absoluto de los relojes, orientación y correspondencia de referencia en dispositivos reales. Un reloj marcado `unknown` sigue bloqueando aceptación métrica.
2. Obtener y revisar una geometría conectada plausible con referencia real confirmada. Una advertencia, una dimensión escrita o la normalización proporcional no satisfacen esa condición.
3. Ejecutar piloto de tres habitaciones con medición independiente y tolerancia aprobada (GAP-065 permanece abierto); medir rendimiento y memoria con duración y cobertura reales.
4. Evaluar puertas/ventanas reales y falsas detecciones. OWLv2 sigue opcional; las pruebas de fallback y banco sintético no miden su eficacia en viviendas.
5. Completar el alcance comercial pendiente fuera de esta misión y la decisión de #71. No se declara cierre físico ni funcional total de las issues.
