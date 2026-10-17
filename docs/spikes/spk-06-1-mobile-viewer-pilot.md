# Spike 06.1: Piloto de Visor Móvil 3D (Fase 06)

**Objetivo:** Validar una escena sintética pequeña en un WebView candidato dentro de la app cliente, con navegación táctil, carga y recuperación. 

## 1. Entradas y preparación (Antes de implementar)
- [ ] **Fuentes verificadas:** Se revisó el `docs/plan-maestro-roomforge.md` y `docs/redefinicion-roomforge.md`.
- [x] **Dependencia WebView:** Se usa `webview_flutter: ^4.8.0` (paquete oficial de Flutter) para renderizar la escena Three.js en el cliente.
- [x] **Dispositivo de prueba:** 
  - Modelo/SKU: Samsung Galaxy A34 (ID ADB `RFCW70SYR5A`), conectado por cable USB.
  - Versión Android: 16
  - WebView del sistema: Android System WebView 154.0.8037.107 (versión activa; la de fábrica es 143.0.7499.192)
- [x] **Fixture de prueba (usado):** escena del visor web (`panel/staff-shell/src/features/editor3d/SceneViewer.tsx`, ruta `/visor3d`), ajustada para cumplir la propuesta:
  - Habitación sintética rectangular de 4 × 3 m y 2,4 m de alto, con suelo.
  - Paredes con una abertura simple: puerta `door_1` de 0,9 m de ancho y 2,1 m de alto, centrada en x = 2 sobre la pared z = 0 (según `docs/api/f06-scene-contract.md`).
  - Cámara inicial a 1,6 m de altura, dentro de la habitación, en (2; 1,6; 2,8), mirando hacia la puerta.
  - Tres cubos de color de 0,5 m como referencias: rojo "Sofá Modular Rojo" (599,99), verde "Mesa de Centro Verde" (249,50) y amarillo "Estantería Amarilla" (179,90).
  - Sin texturas, sombras ni efectos.
- [x] **Registro técnico del fixture:**
  - Unidades: metros.
  - Ejes: Y hacia arriba; X a lo ancho (0 a 4 m); Z a lo profundo (0 a 3 m); origen en la esquina (0, 0, 0) de la habitación, a nivel del suelo.
  - Geometría: 50 triángulos (suelo 2; paredes 12, en 6 paños porque la pared de la puerta se divide en paño izquierdo, paño derecho y dintel; cubos 36). Además, líneas de bordes y una grilla de referencia de 10 × 10 m.
  - Viewport: lienzo fijo de 800 × 500 px, cámara en perspectiva de 75° de campo de visión.
  - Iluminación: ninguna; todos los materiales son `MeshBasicMaterial` (sin luz), con transparencia en suelo y paredes.
  - Recursos: la escena se genera por código, sin archivos externos (modelos, texturas). Hash del recurso usado (blob Git de `SceneViewer.tsx`): `d06b7ace950dc148ffaea5d761dd98b56726c8b2`.

## 2. Registro de corridas (Ejecución)

- **Fecha:** 2026-10-17
- **Commit / Rama:** visor web en `feat/f06-modelo-editable` (`43f629e`); integración WebView y ajuste del fixture en `feat/f06-webview-cliente`.
- **Entorno:** servidor de desarrollo Vite en la PC (`npm run dev -- --host ::`, puerto 5173), expuesto al celular con `adb reverse tcp:5173 tcp:5173`. La app carga `http://localhost:5173/visor3d` (configurable con `--dart-define=ROOMFORGE_VISOR_URL`).
- **Tiempo a primera vista navegable:** promedio de 132 ms en 3 cargas (152 ms, 118 ms y 126 ms), medido en la app de `onPageStarted` a `onPageFinished` del WebView. Con la escena anterior de un solo cubo se midieron 148 ms.
- **CPU / Memoria:** una sola muestra, tomada con la app en la pestaña "Visor 3D" después de mover la cámara, en compilación de depuración (`flutter run`), que consume más que una de release:

| Proceso | CPU (`top`) | Memoria residente (`top`) |
| --- | --- | --- |
| App `com.example.cliente_mobile` | 60 % | 306 MB |
| Proceso del WebView (`sandboxed_process0`) | 20 % | 135 MB |

  `dumpsys meminfo` de la app: TOTAL PSS 459 451 KB (≈ 449 MB), TOTAL RSS 405 991 KB (≈ 396 MB), TOTAL SWAP PSS 130 352 KB. El porcentaje de CPU de `top` es relativo a un núcleo.

## 3. Resultados Funcionales

- **Carga:** Éxito. La escena se muestra completa (suelo, paredes con la puerta y los tres cubos) dentro de la pestaña "Visor 3D" de la app cliente.
- **Recuperación:** Éxito. Prueba: se detuvo el servidor, la app mostró la pantalla de error con "Reintentar"; se volvió a levantar el servidor y se pulsó "Reintentar"; la escena volvió a cargar.
- **Interacción táctil:** Éxito parcial.

| # | Prueba | Resultado |
| --- | --- | --- |
| 1 | Arrastrar con un dedo rota la cámara | Sí |
| 2 | Pellizcar con dos dedos hace zoom | Sí |
| 3 | Arrastrar cada uno de los tres cubos; no atraviesan las paredes (colisiones) | Sí |
| 4 | Tocar cada cubo muestra su nombre y precio | Sí |
| 5 | Tocar fuera del cubo oculta el precio | Sí |
| 6 | El visor entra completo en la pantalla | No |
| 7 | Navegación en primera persona (W/A/S/D) | No (no hay teclado en el móvil) |
| 8 | La abertura (puerta) se ve en la pared | Sí |

## 4. Conclusión y Recomendación

El WebView (`webview_flutter`) es viable para mostrar el visor Three.js en la app cliente: la escena carga rápido (132 ms de promedio en local) y la rotación, el zoom, el arrastre con colisiones y la consulta de precio funcionan con gestos táctiles en un dispositivo físico.

Antes de usarlo en producción se recomienda:

1. **Hacer el lienzo responsive:** el renderer tiene un tamaño fijo de 800 × 500 px y no entra en la pantalla del celular. Debe ajustarse al tamaño del contenedor y escuchar el cambio de tamaño de la ventana.
2. **Ofrecer una vista móvil sin el shell del panel:** el encabezado y la navegación del panel ocupan espacio en el WebView; conviene una ruta o modo de solo visor para la app.
3. **Reemplazar W/A/S/D por un control táctil** (joystick virtual o botones) para la navegación en primera persona.
4. **Revisar el consumo de CPU** (60 % en la app y 20 % en el WebView en la muestra tomada): el bucle de render dibuja en cada cuadro aunque la escena no cambie. Conviene renderizar solo cuando hay interacción y repetir la medición en una compilación de release.
5. **Probar con la escena real** (contrato JSON de `docs/api/f06-scene-contract.md`) antes de cerrar la decisión.

**Corrección aplicada durante el spike:** el clic y el arrastre detectaban el contorno de líneas de cada cubo (objeto hijo sin nombre ni precio), lo que dejaba la página en blanco al hacer clic. Se limitó la detección a los cubos (`intersectObjects(..., false)` y `dragControls.recursive = false`) y se validan nombre y precio antes de mostrarlos.
