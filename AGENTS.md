# RoomForge — Guía de contexto para agentes

> Este archivo le permite a un agente (de cualquier persona/equipo) entender el proyecto, su arquitectura de repositorio único, las convenciones y el estado actual antes de tocar nada.

## 1. Qué es el proyecto

**RoomForge** es un SaaS inmobiliario académico con recorridos 3D, desarrollado como trabajo final de la materia **Ingeniería de Software 1 (SW1)**, ciclo **2026-2**, **Grupo #12**. El proyecto se mantiene en un repositorio único: el código de producto vive en `backend/`, `panel/` y `apps/*_mobile/`, junto con la documentación e integración.

- **Escenario**: inmobiliarias publican inmuebles; agentes capturan videos/fotos para reconstrucción 3D (Meshroom); clientes recorren los inmuebles en 3D, consultan precios, reservan y pagan con token de prueba.
- **Fase actual**: en la base `b6a468a` están AGENCY-2 (registro de agencias) y la autenticación de personal. PB-001/PB-002 (autenticación de clientes) y el registro, login y sesión de la app cliente son históricos y no están presentes en esta base. La app Flutter cliente tiene únicamente su shell inicial; cuenta/sesión, catálogo, cotizaciones, reservas y wallet siguen pendientes.
- **Actualización 2026-10-07:** el párrafo anterior describe una base histórica. El estado vigente por fase está en `docs/plan-maestro-roomforge.md` §1.4.1; la tabla de §6 resume cada superficie.
- **Documentación maestra**: `docs/` — PAPS, Sprint 0–3, trazabilidad de IDs (PB/HU/CP/GAP) siguiendo el formato del documento modelo (Grupo #12).

## 2. Cómo trabajar acá (primero leé esto)

1. **Siempre verificá el estado antes de editar**: `git status`, `git branch --show-current` y, si vas a tocar backend, corré la suite (`pytest`). El working tree puede tener cambios en curso de otra sesión.
2. **Después de clonar**: `git clone <url>` — el código de producto está versionado directamente en las carpetas de este repositorio; no se requieren submódulos.
3. **No commitees ni pushees sin que el humano lo pida explícitamente.** El dueño del repo decide cuándo y cómo se agrupan los commits.
4. **El archivo `docs/diagramas/Diagrama1.eapx` es binario de Enterprise Architect**: está excluido de la mayoría de los cambios (EA suele tenerlo abierto y lo re-modifica).
5. **Uso de SDD/OpenSpec**: los cambios sustanciales se planifican con el flujo SDD (proposal → spec → design → tasks → apply → verify → archive) bajo `openspec/changes/<cambio>/`, con artefactos en español y trazabilidad a los IDs del sprint.

## 3. Repositorio único (importante)

El repositorio `Fivoryu/sw1_pro_final_2026_2` contiene tanto la documentación como el código de producto. Estas carpetas son directorios normales del repositorio, no submódulos:

| Carpeta | Superficie | Stack |
| --- | --- | --- |
| `backend/` | API FastAPI monolítica modular | FastAPI · SQLAlchemy · Alembic · PostgreSQL |
| `panel/` | Panel web admin/agente | React · TypeScript · Vite |
| `apps/captura_mobile/` | App de captura del agente | Flutter |
| `apps/cliente_mobile/` | App del cliente | Flutter |

- **Regla**: los cambios de código de producto se realizan directamente en la carpeta correspondiente de este repositorio. La documentación, OpenSpec y el resto de la integración también se mantienen aquí; no hay repositorios hijos que sincronizar.

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
├── backend/         # API FastAPI (ver §5)
├── panel/           # Panel web React (estructura inicial)
├── apps/            # Apps Flutter (estructura inicial)
├── openspec/        # Cambios SDD: openspec/changes/{registro-cliente, autenticacion, prueba-hu001}
├── infra/           # Docker Compose local (compose.postgres.yml: postgres:16-alpine, puerto 5434)
├── contracts/       # Contratos Solidity/Hardhat (escrow de token de prueba) — pendiente
├── worker3d/        # Worker de reconstrucción 3D (Python + Meshroom) — pendiente
└── skills/          # Skills de documentación del proyecto (ver §8)
```

## 5. Backend (FastAPI) — estado de implementación

Stack: **FastAPI · SQLAlchemy 2.x (sync, driver psycopg) · Alembic · PostgreSQL · Argon2id · PyJWT · pytest**.

> **Vigencia de la base:** el árbol PB-001/PB-002 y las cifras de pruebas más abajo son un registro histórico anterior a AGENCY-2. La base `origin/main` usada por `feat/roomforge-mobile-3d` es `b6a468a`: hoy `/api/v1/auth/*` corresponde a autenticación de personal, y no hay autenticación de cliente, catálogo ni reservas. El contrato nuevo separa las rutas de clientes bajo `/api/v1/customer/auth/*`; aún no están implementadas.

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

- **Histórico de PB-001/PB-002 (base anterior a AGENCY-2, no verificar como comportamiento actual):** se reportaron `POST /api/v1/auth/register`, `POST /api/v1/auth/login`, refresh/logout y `/me`, **33 tests verdes** y migraciones `0001`+`0002` contra PostgreSQL en 2026-08-24. Esos resultados no acreditan la base `b6a468a`; sus rutas actuales de `/api/v1/auth/*` son de personal.
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
| `backend/` | Identidad de personal y de cliente, agencias, catálogo con publicaciones, fotos (F04) y mobiliario, cotizaciones multi-moneda (BOB, USD y USDT) y reservas con escrow local. |
| `panel/` | Panel de personal (React + TypeScript + Vite): acceso con TOTP, administración de agencias, bandeja de revisión de inmuebles con fotos y administración de tipos de cambio. |
| `apps/captura_mobile/` | App de captura (Flutter): acceso de personal y borradores de inmuebles con moneda y fotos; las pantallas de captura espacial (F07) siguen siendo prototipos. |
| `apps/cliente_mobile/` | App cliente (Flutter): cuenta y sesión de cliente, catálogo público con filtros, detalle, fotos y moneda de visualización; cotización, wallet y reservas sin interfaz. |
| `worker3d/`, `contracts/` | 🔲 Sin trabajo aún |

## 7. Documentación y trazabilidad (convenciones)

- **IDs canónicos**: `PB-XXX` (product backlog), `HU-XXX` (historias), `CP-XXX` (casos de prueba), `GAP-XXX` (pendientes del proyecto), `GAP-CH2-XXX` (gaps del modelo). Fuente: `docs/sprint-0/ids-trazabilidad.md`.
- **Sprints**: `docs/scrum/sprint-N/` con los 8 módulos del modelo (planning, proceso por HU, daily, review, retrospective, burndown/burnup, esfuerzo, taskboard).
- **Regla de diagramas**: solo se referencia el **tipo** de diagrama y su ubicación; **no se embeben imágenes** ni se inventa un tipo que el modelo no especifique (GAP-CH2-001..007).
- **Regla de gaps**: un GAP no se "arregla silenciosamente" ni se inventa el dato faltante; se documenta y se deja la marca.
- **Idioma**: toda la documentación de Ingeniería de Software se escribe en **español profesional y neutral**; el código y sus identificadores en **inglés** (convención del proyecto).
- **Rutas HTTP públicas**: los paths y endpoints siempre usan nombres en **inglés**. En la base `b6a468a`, `/api/v1/auth/*` es de personal; el contrato propuesto separa el alta/sesión de cliente en `/api/v1/customer/auth/*`. La ruta histórica `POST /api/v1/auth/register` no debe tratarse como endpoint vigente de esta base.
- **Commits**: conventional commits (`feat|fix|test|docs|chore|refactor(scope): ...`), una unidad de trabajo por commit, **sin atribución de IA**.

## 8. Skills del proyecto

- [documentacion-software](skills/documentacion-software/SKILL.md): usar para generar documentación modular y verificable de Ingeniería de Software en este proyecto.
- [diagramas-uml-ea](skills/diagramas-uml-ea/SKILL.md): usar para crear diagramas UML en Enterprise Architect vía MCP, empezando por el patrón validado de diagrama de comunicación con business objects.
- [github-invitations](skills/github-invitations/SKILL.md): usar para invitar colaboradores a repositorios de GitHub con permisos explícitos y verificación de estado.
- [university-repositories](skills/university-repositories/SKILL.md): usar para crear y nombrar repositorios de GitHub de proyectos universitarios, incluidos monorepos y submódulos.

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
- **GAP-087**: CP-003..CP-013 sin ejecutar; CP-001 y CP-002 cuentan con evidencia.
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
