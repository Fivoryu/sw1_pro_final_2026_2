# Apply progress — autenticacion

## Estado

- Fase: `sdd-apply`
- Cambio: `autenticacion` (PB-002 / HU-002)
- Artifact store solicitado: `hybrid`; `openspec` es la autoridad local de tasks y apply-progress.
- Estado estructurado consumido: `applyState: ready`, `nextRecommended: apply`, `blockedReasons: []`, `actionContext.mode: repo-local`, `allowedEditRoots: [workspace root]`.
- Runtime attempt authority: intento 1 activo, work unit `sdd-apply T1-T5 backend auth slice`, presupuesto nativo 3 intentos / 1650 líneas; se continuó el intento existente reportado por `gentle-ai sdd-status`.
- Delivery: `auto-chain`, `stacked-to-main`; PRs/push no ejecutados por responsabilidad del parent.
- Rama actual: `feat/autenticacion/t1-core`.

## TDD Cycle Evidence

| Unidad | RED | GREEN | TRIANGULATE | REFACTOR |
| --- | --- | --- | --- | --- |
| T1 — núcleo de tokens | `pytest -q tests/test_tokens_core.py` falló en colección con `ModuleNotFoundError: No module named 'jwt'` antes de implementar el núcleo. | Después de agregar PyJWT, settings, clock y servicio de tokens: `4 passed`. | Pendiente de completar con la suite acumulada y revisión de casos de configuración/seguridad. | Ruff aplicado al núcleo; pendiente cierre de la unidad tras verificación y commit. |

## T1 completado

- Checkbox persistido: `openspec/changes/autenticacion/tasks.md` T1 marcado `[x]`.
- Implementado:
  - `backend/app/core/config.py`: secreto JWT fail-closed y TTLs configurables.
  - `backend/app/core/clock.py`: `ClockProtocol` y `SystemClock` UTC aware.
  - `backend/app/core/tokens.py`: PyJWT HS256, claims `sub/sid/type/iat/exp`, verificación contra clock inyectado, refresh opaco y SHA-256.
  - `backend/app/core/security.py`: verificación Argon2id uniforme con hash ficticio, reutilizando el adaptador existente.
  - `backend/.env.example`: placeholders no operativos.
  - `backend/pyproject.toml`: dependencia `PyJWT>=2.8,<3`.
  - `backend/tests/test_tokens_core.py`: pruebas de firma, claims, TTL, rechazo y hash.
- Dependencia instalada únicamente en el venv del proyecto con `uv pip install --python .venv/Scripts/python.exe PyJWT>=2.8,<3` (`PyJWT 2.13.0`); no se instaló PostgreSQL.

## Verificación acumulada

- Ejecutado: `cd backend && .venv/Scripts/python.exe -m pytest -q tests/test_tokens_core.py` → `4 passed`.
- Ejecutado: `cd backend && .venv/Scripts/python.exe -m ruff check app/core tests/test_tokens_core.py` → verde después de autofix de imports.
- La suite completa y las verificaciones de migración quedan para T2–T5.

## Archivos y cambios

- Código/test/configuración modificados según T1 arriba.
- `0001_crear_usuario_global.py`, `docs/diagramas/Diagrama1.eapx` y el archivo no relacionado `nul` no fueron modificados por esta unidad.

## Pendiente

- T2, T3, T4 y T5 siguen sin completar.
- Acciones parent-owned permanecen diferidas byte-for-byte: bounded review y gates/PR chain.
- No se ejecutaron PRs, push ni gates de entrega.

## Desviaciones y riesgos

- El `sdd-status` nativo reportó `artifactStore: openspec` aunque el contexto de fase solicita `hybrid`; se usó OpenSpec como fuente autoritativa y se debe persistir también el espejo Engram al cierre si el backend vuelve a estar disponible.
- El servidor Engram no respondió durante la lectura (`127.0.0.1:7437`); no se afirma persistencia Engram en este punto.
- La migración real y PostgreSQL permanecen fuera de alcance; se verificará offline como exige GAP-092.
