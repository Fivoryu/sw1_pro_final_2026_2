# Reinicio de implementación de RoomForge

## Objetivo

Retirar la implementación de producto existente del checkout actual para poder redefinir RoomForge como un proyecto académico de bajo consumo, conservando la documentación y el historial de planificación.

## Problema y motivo

La solución documentada incluye reconstrucción de interiores, recorridos 3D y superficies móviles, con costos y complejidad que el equipo quiere evitar. El usuario autorizó retirar la implementación actual —incluidos código, pruebas, migraciones y configuraciones asociadas— antes de redefinir el alcance del producto.

## Alcance autorizado

- Retirar fuentes, pruebas, migraciones de base de datos y configuración de ejecución/construcción del backend, panel web y app cliente móvil en los worktrees actuales.
- Retirar la configuración de infraestructura de ejecución existente en la raíz, incluido el Compose local de PostgreSQL.
- Conservar documentación humana y artefactos OpenSpec en la raíz y submódulos; conservar los `README.md`, `AGENTS.md`, `skills/`, diagramas y demás archivos documentales.
- Conservar `.git/`, `.gitmodules`, `.gitignore`, datos locales/ignorados, caches, archivos de entorno reales, volúmenes de bases de datos, artefactos de herramientas y archivos de identidad desconocida.
- No borrar submódulos completos, worktrees externos, ramas remotas, repositorios remotos ni el archivo binario `docs/diagramas/Diagrama1.eapx`.
- No reescribir aún la documentación de requisitos existente: permanecerá como historial hasta que el usuario apruebe la nueva definición.
- El inventario no identificó implementación en `apps/captura_mobile/`, `contracts/` ni `worker3d/`; conservar sus documentos y verificar esos límites sin purgar carpetas.

## Restricciones y evidencia inicial

- El estado inicial tenía cambios locales en la raíz, `backend/` y `apps/cliente_mobile/`; el usuario autorizó incluir los cambios locales de implementación en la retirada. Los cambios de documentación/OpenSpec y archivos de propósito incierto se preservan.
- La raíz estaba en `main`; `backend/`, `panel/` y `apps/captura_mobile/` estaban en `main`; `apps/cliente_mobile/` estaba detached. También existen worktrees fuera del checkout, que quedan fuera de alcance.
- Comprobación base antes de cambios, desde `backend/`: `../.venv/Scripts/python.exe -m pytest tests -q` — salida 1; 291 passed, 6 errores de preparación de pruebas PostgreSQL por conexión no disponible a `localhost:5434`, 3 warnings, 270.49 s. Es evidencia previa a la retirada, no una validación final.
- TDD: no aplicable a la tarea de eliminación (no se añade ni cambia comportamiento de producto). No se inventa evidencia RED/GREEN. Después de borrar tests/código no habrá suite de producto que ejecutar; la verificación será estructural y de preservación documental.
- Política de entrega: el usuario no pidió commits ni push y `AGENTS.md` prohíbe hacerlos sin petición explícita. Los cambios locales no se confirmarán hasta contar con esa autorización.

## Tareas

- [x] **RST-01 — Explorar y fijar límites de conservación.** Revisar repositorios, documentación y estado inicial; separar código/configuración de documentos y anotar las limitaciones de verificación.
- [x] **RST-02 — Crear ramas de trabajo locales.** Creadas `chore/roomforge-reset-01a0d0ec` en la raíz, `backend/`, `panel/` y `apps/cliente_mobile/`; no se descartaron cambios existentes.
- [x] **RST-03 — Retirar implementación del backend.** La inspección no encontró código/tests/migraciones ni configuración de ejecución antigua, salvo `backend/.env.example`, que el usuario decidió conservar por ahora; no se leyó ni modificó y el `.env` real local permanece intacto.
- [x] **RST-04 — Retirar implementación del panel.** La inspección no encontró código, pruebas ni configuración antigua en `src/`, `e2e/` y manifiestos; `README.md` y OpenSpec permanecen.
- [x] **RST-05 — Retirar implementación de la app cliente.** La inspección no encontró fuentes/tests ni scaffold móvil; se restauró el README interno y se conservó el README de la app con su endpoint actualizado a `/api/v1/auth/register`.
- [x] **RST-06 — Retirar configuración de infraestructura anterior.** El Compose de PostgreSQL fue eliminado; `contracts/` y `worker3d/` conservan sus README.
- [x] **RST-07 — Verificar alcance y conservación.** La auditoría final confirmó ausencia de código en las superficies escaneadas, documentación protegida presente tras restauraciones, cambios sin stage y `.env.example` conservado por decisión explícita.
- [x] **RST-11 — Restaurar documentación interna eliminada.** Los cuatro README internos fueron restaurados desde `HEAD`; los diff-status y diff-check dirigidos quedaron limpios y el control de presencia no encontró ausencias.
- [x] **RST-12 — Resolver configuración residual del backend.** La herramienta bloqueó la lectura de `backend/.env.example` por posible sensibilidad; el usuario decidió conservarlo por ahora. No se leyó ni modificó el archivo y se preservó el `.env` real.
- [ ] **RST-08 — Acordar la nueva definición del producto (pendiente).** El usuario definirá el nuevo alcance en otro chat con Astra; no modificar requisitos ni implementar hasta que comparta la definición acordada.
- [ ] **RST-09 — Confirmar los cambios en Git.** Pendiente de petición explícita del usuario; no hacer commit ni push automáticamente.
- [ ] **RST-10 — Desbloquear la ruta de escritura delegada.** Para futuras modificaciones multiarchivo, encontrar un escritor delegado capaz de escribir/eliminar dentro de superficies explícitas. La retirada actual la ejecutó manualmente el usuario; no sustituir esta limitación por edición inline.

## Criterios de aceptación

1. La implementación está ausente en las superficies verificadas; la única configuración residual confirmada es `backend/.env.example`, conservada por decisión explícita del usuario, además del `.env` real local protegido.
2. Documentación, OpenSpec, README, instrucciones del proyecto, diagramas y metadatos de submódulos permanecen intactos.
3. No se limpian caches, secretos/configuración local ignorada, datos, worktrees externos ni archivos de propósito incierto.
4. La suite base y cualquier limitación se informan fielmente; ninguna prueba se declara pasada por haber eliminado su código.
5. No se crea una nueva implementación hasta acordar el alcance académico de bajo consumo.

## Progreso y siguiente paso

- Estado: el usuario realizó manualmente la retirada; Git muestra eliminaciones en backend, panel, cliente móvil y Compose de PostgreSQL. No se han confirmado ni enviado cambios.
- Las ramas locales `chore/roomforge-reset-01a0d0ec` siguen activas en raíz, backend, panel y cliente.
- Verificación read-only completada: no se encontró código fuente/test/migración en las superficies examinadas ni configuración antigua listada; las rutas documentales protegidas de raíz/OpenSpec/README siguen presentes. No se informaron cambios staged. `apps/captura_mobile/` está limpio.
- Los cuatro README internos eliminados fueron restaurados desde `HEAD`; las comprobaciones dirigidas confirmaron su presencia y diff limpio.
- `apps/cliente_mobile/README.md` fue editado para cambiar la ruta de registro a `/api/v1/auth/register`; se conserva ese cambio. Los diff-checks dirigidos no reportaron whitespace; Git emitió avisos LF/CRLF en OpenSpec HU007.
- La auditoría final encontró `backend/.env.example`; el usuario decidió conservar ese ejemplo por ahora. No se inspeccionó ni alteró su contenido, y el `.env` real permanece intacto.
- La auditoría integral confirmó ausencia de implementación en las superficies escaneadas y documentación protegida presente. La suite base continúa como única evidencia de pruebas: 291 passed y 6 errores ambientales PostgreSQL a `localhost:5434`; no se ejecutaron pruebas después de retirar el código.
- Siguiente paso: esperar la definición acordada en otro chat con Astra; después actualizar documentación académica según esa definición.
- No hay commit ni push; las eliminaciones permanecen locales y sin stage.
