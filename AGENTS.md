# RoomForge — Guía de contexto para agentes

> Este archivo le permite a un agente (de cualquier persona/equipo) entender el proyecto, su arquitectura multi-repo, las convenciones y el estado actual antes de tocar nada.

## 1. Qué es el proyecto

**RoomForge** es un SaaS inmobiliario académico con recorridos 3D, desarrollado como trabajo final de la materia **Ingeniería de Software 1 (SW1)**, ciclo **2026-2**, **Grupo #12**. El monorepo actual es el repositorio de coordinación; el código de producto vive en 4 repositorios individuales conectados como submódulos (ver §3).

- **Escenario**: inmobiliarias publican inmuebles; agentes capturan videos/fotos para reconstrucción 3D (Meshroom); clientes recorren los inmuebles en 3D, consultan precios, reservan y pagan con token de prueba.
- **Fase actual**: backend implementado para **PB-001 (registro de cliente)** y **PB-002 (autenticación y sesión)**; el resto de superficies (panel web, apps móviles, worker 3D, contratos) está en estructura inicial.
- **Documentación maestra**: `docs/` — PAPS, Sprint 0–3, trazabilidad de IDs (PB/HU/CP/GAP) siguiendo el formato del documento modelo (Grupo #12).

## 2. Cómo trabajar acá (primero leé esto)

1. **Siempre verificá el estado antes de editar**: `git status`, `git branch --show-current` y, si vas a tocar backend, corré la suite (`pytest`). El working tree puede tener cambios en curso de otra sesión.
2. **Después de clonar**: `git clone --recurse-submodules <url>` — las carpetas de producto son submódulos y sin `--recurse-submodules` quedan vacías.
3. **No commitees ni pushees sin que el humano lo pida explícitamente.** El dueño del repo decide cuándo y cómo se agrupan los commits.
4. **El archivo `docs/diagramas/Diagrama1.eapx` es binario de Enterprise Architect**: está excluido de la mayoría de los cambios (EA suele tenerlo abierto y lo re-modifica).
5. **Uso de SDD/OpenSpec**: los cambios sustanciales se planifican con el flujo SDD (proposal → spec → design → tasks → apply → verify → archive) bajo `openspec/changes/<cambio>/`, con artefactos en español y trazabilidad a los IDs del sprint.

## 3. Arquitectura multi-repo (importante)

El monorepo (`Fivoryu/sw1_pro_final_2026_2`) contiene **submódulos git** para el código de producto:

| Carpeta en el monorepo | Repositorio individual | Superficie |
| --- | --- | --- |
| `backend/` | [`sw1_pro_final_backend_2026_2`](https://github.com/Fivoryu/sw1_pro_final_backend_2026_2) | API FastAPI monolítica modular |
| `panel/` | [`sw1_pro_final_frontend_2026_2`](https://github.com/Fivoryu/sw1_pro_final_frontend_2026_2) | Panel web admin/agente (React) |
| `apps/captura_mobile/` | [`sw1_pro_final_captura_mobile_2026_2`](https://github.com/Fivoryu/sw1_pro_final_captura_mobile_2026_2) | App de captura del agente (Flutter) |
| `apps/cliente_mobile/` | [`sw1_pro_final_cliente_mobile_2026_2`](https://github.com/Fivoryu/sw1_pro_final_cliente_mobile_2026_2) | App del cliente (Flutter) |

- **Regla**: los cambios de código de producto se trabajan **dentro del repositorio individual** correspondiente (o en la carpeta vía submódulo) y se pushean allí. El monorepo conserva documentación, OpenSpec e integración.
- Para actualizar el submódulo del monorepo tras un push externo: `git submodule update --remote <carpeta>` (o entrar a la carpeta y `git pull`), luego commit del gitlink en el monorepo.

## 4. Estructura del monorepo

```text
proyecto_final/
├── docs/            # Documentación de Ingeniería de Software
│   ├── scrum/       #   Sprint 0–3 (planning, proceso por HU, daily, review, retro, burndown, esfuerzo, taskboard)
│   │   ├── sprint-0-requerimientos/   # Backlog HU, casos de uso, planificación, infraestructura
│   │   ├── sprint-1/  sprint-2/  sprint-3/
│   │   └── sprint-1/evidencia/        # Transcriptos de ejecución de pruebas (p.ej. CP-001)
│   ├── modelo_doc/   # Documento modelo Grupo #12 (PDF) + guía estructural del CAPITULO 2 + extractos
│   ├── sprint-0/     # Análisis: trazabilidad de IDs, tipos de diagramas, PAPS
│   └── diagramas/    # Modelos Enterprise Architect (.eapx)
├── backend/         # 🔗 submódulo — API FastAPI (ver §5)
├── panel/           # 🔗 submódulo — panel web React (estructura inicial)
├── apps/            # 🔗 submódulos — apps Flutter (estructura inicial)
├── openspec/        # Cambios SDD: openspec/changes/{registro-cliente, autenticacion, prueba-hu001}
├── infra/           # Docker Compose local (compose.postgres.yml: postgres:16-alpine, puerto 5434)
├── contracts/       # Contratos Solidity/Hardhat (escrow de token de prueba) — pendiente
├── worker3d/        # Worker de reconstrucción 3D (Python + Meshroom) — pendiente
└── skills/          # Skills de documentación del proyecto (ver §8)
```

## 5. Backend (FastAPI) — estado de implementación

Stack: **FastAPI · SQLAlchemy 2.x (sync, driver psycopg) · Alembic · PostgreSQL · Argon2id · PyJWT · pytest**.

```text
backend/
├── app/
│   ├── main.py            # create_app() — registro de routers, fail-closed de JWT al arrancar
│   ├── core/              # config.py (pydantic-settings, .env), security.py (Argon2id),
│   │                      # clock.py (clock inyectable), tokens.py (JWT access + refresh opaco SHA-256)
│   ├── modules/identity/  # router/schemas/service/repository/models — registro + autenticación
│   └── db/                # session.py (engine lazy desde DATABASE_URL), base.py
├── alembic/versions/      # 0001_crear_usuario_global.py, 0002_crear_sesion.py
└── tests/                 # test_registro.py, test_autenticacion.py, test_session_repository.py, test_tokens_core.py
```

- **Implementado y verificado (VERIFY PASS, 2026-08-24)**: `POST /api/v1/auth/registro` (201/409/422), `POST /api/v1/auth/login` (access JWT 15 min + refresh opaco), `POST /api/v1/auth/refresh` (rotación atómica), `POST /api/v1/auth/logout` (204 idempotente), `GET /api/v1/auth/me` (sesión validada server-side, inactividad sliding 30 min). **33 tests verdes**, ruff limpio, pyright CLI 0 errores. Migraciones `0001`+`0002` ejecutadas contra PostgreSQL real (Docker).
- **Entorno local**: `.venv/` en la raíz del monorepo (no commiteado); `backend/.env` local gitignored (DATABASE_URL, JWT_SECRET); PostgreSQL vía `infra/docker/compose.postgres.yml` (puerto 5434).

### Comandos útiles (desde `backend/`)

```bash
# Suite completa de tests (no requiere PostgreSQL; usa fakes + dependency_overrides)
<raiz>/.venv/Scripts/python.exe -m pytest tests -q

# Lint y tipos (autoritativos; el diagnóstico del LSP puede dar falsos positivos por intérprete stale)
<raiz>/.venv/Scripts/python.exe -m ruff check app tests
<raiz>/.venv/Scripts/pyright.exe app tests

# Migraciones reales (requiere PostgreSQL arriba + backend/.env)
<raiz>/.venv/Scripts/python.exe -m alembic upgrade head
<raiz>/.venv/Scripts/python.exe -m alembic current

# Levantar PostgreSQL local
docker compose -f infra/docker/compose.postgres.yml up -d
```

## 6. Estado de las superficies

| Superficie | Estado |
| --- | --- |
| `backend/` | ✅ Registro (PB-001) + autenticación/sesión (PB-002) implementados y verificados; pruebas CP-001 ejecutadas contra PostgreSQL real |
| `panel/` | 🔲 Estructura inicial (React + TypeScript + Vite), sin código |
| `apps/captura_mobile/` | 🔲 Estructura inicial (Flutter), sin código |
| `apps/cliente_mobile/` | 🔲 Estructura inicial (Flutter), sin código |
| `worker3d/`, `contracts/` | 🔲 Sin trabajo aún |

## 7. Documentación y trazabilidad (convenciones)

- **IDs canónicos**: `PB-XXX` (product backlog), `HU-XXX` (historias), `CP-XXX` (casos de prueba), `GAP-XXX` (pendientes del proyecto), `GAP-CH2-XXX` (gaps del modelo). Fuente: `docs/sprint-0/ids-trazabilidad.md`.
- **Sprints**: `docs/scrum/sprint-N/` con los 8 módulos del modelo (planning, proceso por HU, daily, review, retrospective, burndown/burnup, esfuerzo, taskboard).
- **Regla de diagramas**: solo se referencia el **tipo** de diagrama y su ubicación; **no se embeben imágenes** ni se inventa un tipo que el modelo no especifique (GAP-CH2-001..007).
- **Regla de gaps**: un GAP no se "arregla silenciosamente" ni se inventa el dato faltante; se documenta y se deja la marca.
- **Idioma**: toda la documentación de Ingeniería de Software se escribe en **español profesional y neutral**; el código y sus identificadores en **inglés** (convención del proyecto).
- **Commits**: conventional commits (`feat|fix|test|docs|chore|refactor(scope): ...`), una unidad de trabajo por commit, **sin atribución de IA**.

## 8. Skills del proyecto

- [documentacion-software](skills/documentacion-software/SKILL.md): usar para generar documentación modular y verificable de Ingeniería de Software en este proyecto.
- [diagramas-uml-ea](skills/diagramas-uml-ea/SKILL.md): usar para crear diagramas UML en Enterprise Architect vía MCP, empezando por el patrón validado de diagrama de comunicación con business objects.

## 9. SDD / OpenSpec

Los cambios de producto se planifican con **SDD** (Spec-Driven Development). Hay dos backends de artefactos activos: `openspec/changes/<cambio>/` (archivos) y Engram (memoria persistente, tópicos `sdd/<cambio>/...`).

| Cambio | PB/HU | Estado |
| --- | --- | --- |
| `registro-cliente` | PB-001 / HU-001 | Archivado (backend implementado) |
| `autenticacion` | PB-002 / HU-002 | Archivado (backend implementado) |
| `prueba-hu001` | CP-001 real | Archivado (ejecución contra PostgreSQL real + evidencia) |

Para un cambio nuevo: seguir el pipeline SDD completo y persistir ambos backends. No inventar artefactos de fases que el dispatcher nativo no haya autorizado.

## 10. Gaps abiertos relevantes

- **GAP-092**: migraciones del Sprint 1 pendientes contra PostgreSQL real — solo `0001`/`0002` ejecutadas; quedan 12 tablas.
- **GAP-087**: CP-002..CP-013 sin ejecutar (solo CP-001 tiene evidencia).
- **GAP-073**: asignación de responsables de pruebas/documentación pendiente.
- **GAP-088**: diagramas UML del Sprint 1 pendientes de creación en Enterprise Architect.
- **GAP-084**: fechas exactas del Sprint 1 no confirmadas.

## 11. Reglas duras de colaboración

1. No commitear/pushear sin autorización explícita del humano.
2. No tocar `docs/diagramas/Diagrama1.eapx` (binario EA, lockeado por la app).
3. No romper la suite de tests del backend ni introducir errores de pyright/ruff.
4. No silenciar GAPs ni inventar evidencia (documentación académica verificable).
5. Los diagnósticos del LSP local pueden ser falsos positivos (intérprete stale): usar **pyright CLI + ruff + pytest** como árbitros reales.
6. Ante ambigüedad de alcance: preguntar antes de construir.
