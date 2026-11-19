# Aplicación y verificación

- [x] Auditar F07-01..33 y preservar el informe original.
- [x] Implementar protecciones métricas e integridad ZIP en los límites backend/worker/panel.
- [x] Endurecer grabador, referencia codificada, persistencia y reintentos móviles.
- [x] Implementar renovación de lease, ownership, streaming y recuperación del resultado.
- [x] Preparar imagen y overlay existentes para runtime nativo CPU.
- [x] Ejecutar pruebas enfocadas y regresión amplia; conservar fallos iniciales y correcciones.
- [x] Aplicar `0036` contra PostgreSQL real aislado y verificar rollback/re-upgrade (integración 18/11/2026; fila histórica conservada).
- [x] Construir imagen independiente en Docker Linux y ejecutar su smoke nativo durante build (integración 18/11/2026; no se desplegaron servicios).
- [ ] Ejecutar QA física en S23 FE/A53 y las cuatro rotaciones.
- [ ] Medir tres habitaciones y presupuesto 30/90/300 s con tolerancia de negocio aprobada.
- [ ] Resolver alcance comercial de #63 y comparación/decisión de #71.

La matriz y los comandos de verificación se conservan en `odd/tasks/f07-audit-hardening.md`.
No se archiva el cambio como aceptación física completa. Engram no está disponible en esta sesión; no se inventa persistencia remota.

## Revisión independiente R01–R12

- [x] Reproducir R02/R03/R04/R05/R08/R09 con seis pruebas negativas antes de corregir.
- [x] Sustituir descarte de `onStop` por finalización/empaquetado y recuperación de MP4 finalizado.
- [x] Cerrar invariantes de retención, intentos, escena persistida y procedencia del servidor.
- [x] Separar I/O/CRC de transacciones y probar carrera de completado/purga, incluido ZIP de 149 MiB.
- [x] Recuperar backup ante raíz inválida y conciliar bytes de capturas históricas.
- [x] Acotar caché privada y recuperar aceptación sin sobrescribir revisiones.
- [ ] Medir offset absoluto MP4/Camera2/IMU en dispositivo (R11).

Resultados, fallos conservados y límites: `odd/tasks/f07-residual-hardening.md`.

## Integración con Trevor, 18/11/2026

- [x] Comparar 26 commits remotos con 59 diffs locales y 33 archivos nuevos; conservar la fuente.
- [x] Resolver semánticamente escala, referencia, candidatos, aberturas y caché, preservando ambos aportes.
- [x] Verificar regresión backend, worker, panel, Flutter, JVM y geometría del cliente; probar integración y persistencia.
- [x] Separar artefactos privados y preparar informe en español con lista exacta del delta, sin commit/push/PR.
- [ ] Aceptación física: relojes, dispositivos/rotaciones, referencia y geometría reales, piloto y tolerancias.

Los registros `odd/tasks/f07-audit-hardening.md` y `f07-residual-hardening.md` arriba citados
pertenecen a la fuente histórica de solo lectura y no se importan como evidencia nueva.
Resultados de esta ejecución: [verificación de integración](../../../docs/integracion/f07-20261118/verificacion.md).
