# Contexto SDD — RoomForge

## Identificación

- Proyecto: RoomForge, monorepo académico de Ingeniería de Software 1.
- Ciclo: 2026-2, Grupo #12.
- Proyecto/slug: `sw1_pro_final_2026_2`.
- Cambio previsto: `hu004-alta-inmobiliaria`.
- Alcance posterior: completar HU-004. HU-005 y HU-006 quedan fuera.
- Almacén: híbrido (OpenSpec + Engram).
- Ejecución: interactiva.
- Estrategia de entrega: `ask-on-risk`.
- Límite explícito: 600 líneas modificadas.

## Stack detectado

- Backend: FastAPI, SQLAlchemy 2.x, PostgreSQL, Alembic, Argon2id, PyJWT y pytest.
- Panel web: React, TypeScript y Vite.
- Aplicaciones móviles: Flutter.
- Integración local: Docker Compose + Floci.
- Arquitectura de repositorio: monorepo con submódulos para backend, panel y aplicaciones móviles.

## Pruebas y calidad

Desde la raíz, con el entorno virtual existente:

- Tests: `.venv/Scripts/python.exe -m pytest backend/tests -q`
- Lint: `.venv/Scripts/python.exe -m ruff check backend/app backend/tests`
- Tipos: `.venv/Scripts/pyright.exe backend/app backend/tests`
- Migraciones: `.venv/Scripts/python.exe -m alembic -c backend/alembic.ini upgrade head`

El proyecto exige modo TDD estricto. La documentación de Ingeniería de Software se redacta en español profesional y neutral; el código y sus identificadores, en inglés.

## Convenciones y restricciones

- Seguir SDD: explore → proposal → spec → design → tasks → apply → verify → archive.
- Mantener IDs y trazabilidad existentes (`PB`, `HU`, `CP`, `GAP`).
- Usar evidencia real y conservar gaps; no inventar requisitos ni resultados.
- No modificar `docs/diagramas/Diagrama1.eapx`.
- No realizar commits ni pushes durante la inicialización.
- El backend local permanece en su rama actual; la referencia informada para trabajo posterior es la rama remota `feature/tenant-hu04-06`, sin cambiarla durante init.

## Evidencia consultada

- `README.md`
- `AGENTS.md`
- `backend/pyproject.toml`
- `.gitmodules`
- `.atl/skill-registry.md`
- Cambios OpenSpec archivados: `registro-cliente`, `autenticacion`, `prueba-hu001`.

## Gaps de inicialización

- `GAP-INIT-001`: el servidor Engram no respondió en `http://127.0.0.1:7437`; el contexto híbrido quedó escrito en OpenSpec, pero la persistencia Engram requiere que el servicio vuelva a estar disponible.
- CodeGraph estaba presente, pero su servidor MCP no estaba inicializado; la exploración estructural se completó mediante documentación y configuración existentes.
