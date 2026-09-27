# F02 — Base de aplicación, UX y automatización

## Objetivo

Completar únicamente F02 del `plan-maestro-roomforge.md`: base API y modularidad, esquema/migraciones iniciales, prototipos navegables de las tres superficies y CI inicial reproducible. No convertir los prototipos en los flujos de negocio de F03–F10.

## Autoridad y alcance

- Requisitos autorizados exclusivamente: `docs/redefinicion-roomforge.md` y `docs/plan-maestro-roomforge.md` (F02.1–F02.4). La integración de estos documentos en `origin/main` está pendiente de la finalización F01.
- El usuario eligió F02 según el plan y rechazó ampliar este cambio a F03–F10. No implementar sus APIs, reglas de negocio, esquemas o integración end-to-end en esta rama.
- El alta pagada de agencias y las suscripciones quedan fuera del MVP según la redefinición.
- F02.1 debe definir estructura modular, validaciones, errores homogéneos, paginación y configuración; documentar contrato y disponibilidad. `/api/v1/listings` es un ejemplo no aprobado, no una ruta autorizada.
- F02.2 debe verificar creación desde base vacía y actualización desde una versión anterior cuando corresponda; documentar recuperación/rollback sin prometer reversibilidad universal.
- F02.3 entrega mapa de pantallas, navegación y contratos de estado para login, gestión, publicación, catálogo, selección y reserva. Es prototipado UX, no implementación funcional de F03–F10. Revisar recorridos antes del detalle visual; cubrir carga, vacío, error, offline y permisos, accesibilidad, foco, contraste y confirmación de acciones irreversibles.
- F02.4 fija runners/versiones desde manifiestos reales, checks separados por superficie y paridad local/CI; proteger secretos y no desplegar desde contribuciones no confiables. No inventar cobertura numérica.
- Decisiones directas del usuario para fases futuras: representar solicitud/aprobación de acceso temporal de siete días; calcular ofertas como precio base más ajustes elegidos y usar dos decimales. En F02 solo pueden aparecer como estados/reglas de prototipo; no se implementa su lógica comercial. Moneda y otras condiciones comerciales siguen pendientes en las fuentes autorizadas.
- Asignación UX aprobada por el usuario: todo el borrador del agente (captura, ambientes, geometría/objetos y preparación de oferta) se realiza en la app Android de captura; el panel web cubre administración/revisión; la app cliente móvil explora y reserva. F02 implementa solo prototipos.
- No consultar documentos históricos de backlog/BR/HU/IDs como autoridad de producto. No crear issue.

## Modo y entrega

- Flujo ODD directo, por elección explícita del usuario; no ejecutar SDD/OpenSpec para este cambio.
- Strict TDD solicitado previamente por el usuario: aplicar RED → GREEN → TRIANGULATE → REFACTOR a cada cambio de comportamiento. Confirmar el runner real de cada superficie antes de iniciar su tarea; nunca reportar PASS si no se ejecutó.
- Crear commits convencionales por unidad de trabajo en esta rama, con sus pruebas y documentación. Medir líneas añadidas + eliminadas por unidad; si el alcance supera 400 líneas, detenerse para acordar slices/estrategia antes de preparar PRs. No se autoriza `size:exception`.
- Preparar localmente la rama para revisión. No hacer push ni abrir PR sin confirmación explícita al cerrar.

## Estado y coordinación

- Worktree: `D:/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final-f02-base-ux-automation-wt`.
- Rama: `feat/f02-base-ux-automation`, creada desde `origin/main` en `b6a468a20888b5c3272fdea1d4815a27897232ba`.
- El checkout raíz conserva cambios ajenos y no se modifica. Rebasar F02 solo después de que el responsable F01 confirme el push final de sus documentos a `origin/main`.
- F01-T3/T4 fueron reportadas completas; no se realizarán operaciones Docker hasta coordinar pruebas F02.
- Handoff móvil recibido desde `feat/roomforge-mobile-3d`; commits locales, sin push: `64c59c02b51d3db3194a51c4e8fd54dbd5c63843` (shell Flutter; candidato F02), `f9d37842876cb0bbe1b7791b9796a73e7048bdf4` (propuesta/documentación API; fuera de autoridad F02), `de534c779ea723ba3eab7168ca45f5d2449dbb6b` (identidad cliente/migración/tests; fuera de F02) y `f762286` (registro de tarea). El dueño reportó 101 passed/2 skipped, Ruff y Pyright OK, SQLite 0004→0005 OK; PostgreSQL no verificado. Antes de integrar, revisar rutas del commit candidato y confirmar que no acopla el prototipo F02 a la implementación F03 de identidad. No copiar ni integrar los commits fuera de F02.
- F02-T1 cerró con el commit local `a156a53`; F02-T2 está en curso.

## Tareas

- [x] **F02-T1 — Proponer mapa UX y contratos de estado.** **CERRADA.** Entregable aprobado: `docs/ux/f02-surface-map.md`; commit `a156a53`. La aprobación precede al detalle visual.
- [ ] **F02-T2 — Completar la base del contrato API.** **EN CURSO.** Definir límites modulares y convenciones homogéneas de validación/error, paginación y configuración; documentar disponibilidad y contrato. Añadir pruebas de contrato en RED primero. No añadir endpoints de negocio no aprobados.
- [ ] **F02-T3 — Verificar el esquema y el ciclo de migraciones.** Basarse en el head real; probar creación desde cero y actualización desde la versión anterior cuando exista; documentar datos ficticios, rollback/recovery y comandos reproducibles. No añadir tablas de dominios posteriores sin autorización.
- [ ] **F02-T4 — Entregar prototipos UX de las tres superficies.** Implementar los recorridos aprobados en el mapa, con carga/vacío/error/offline/permisos, diseño web adaptable, controles táctiles y accesibilidad. Usar el handoff móvil solo tras verificar commit y límites; mantener lo no ejecutable como prototipo honesto.
- [ ] **F02-T5 — Añadir CI inicial y paridad local.** Configurar checks separados para las superficies presentes, versiones basadas en manifiestos, protección de secretos y fallos visibles; no desplegar infraestructura desde código no confiable.
- [ ] **F02-T6 — Integrar, verificar y preparar revisión.** Ejecutar los runners disponibles, reportar todo PASS/FAIL/SKIP/BLOCKED, medir cada slice y registrar commits/evidencia. Resolver o declarar explícitamente cada verificación PostgreSQL/móvil no disponible. Detenerse antes de publicar.

## Evidencia de cierre

| Tarea | Commit | Verificación observada | Estado |
|---|---|---|---|
| F02-T1 | `a156a53` | `git diff --cached --check` PASS; referencias relativas 2/2 PASS; N/A runtime (documentación sin límite de ejecución) | Hecho |
| F02-T2 | Pendiente | Pendiente | En curso |
| F02-T3 | Pendiente | Pendiente | Pendiente |
| F02-T4 | Pendiente | Pendiente | Pendiente |
| F02-T5 | Pendiente | Pendiente | Pendiente |
| F02-T6 | Pendiente | Pendiente | Pendiente |
