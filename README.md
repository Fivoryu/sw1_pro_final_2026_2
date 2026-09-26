# RoomForge — Repositorio único

SaaS inmobiliario académico con recorridos 3D (ver [documentación del proyecto](docs/README.md)). El código de todas las superficies vive en este repositorio.

## Productos

| Producto | Carpeta | Stack |
| --- | --- | --- |
| API del servidor | `backend/` | FastAPI · PostgreSQL · Alembic · Argon2id |
| Panel web admin/agente | `panel/` | React · TypeScript · Vite |
| App de captura del agente | `apps/captura_mobile/` | Flutter (Android 10+) |
| App del cliente | `apps/cliente_mobile/` | Flutter (Android 10+) |

## Estructura

```text
proyecto_final/
├── docs/          # Documentación de Ingeniería de Software (PAPS, Scrum, Sprint 0–3)
├── apps/          # Apps móviles
│   ├── cliente_mobile/  #   App del cliente: catálogo, recorridos, reservas
│   └── captura_mobile/  #   App de captura del agente (video + fotos + difuminado)
├── panel/         # Panel web admin/agente (React + TypeScript + Vite)
├── backend/       # API FastAPI
├── worker3d/      # Worker de reconstrucción 3D (Python + AliceVision/Meshroom)
├── contracts/     # Contratos Solidity/Hardhat (escrow de token de prueba)
├── infra/         # Docker Compose + Floci (dev), despliegue AWS (ECS Express)
├── scripts/       # Utilidades de automatización del equipo
└── skills/        # Skills de documentación (Pi)
```
    
## Clonado y cambios

Clona el repositorio normalmente; no se requieren submódulos:

```bash
git clone https://github.com/Fivoryu/sw1_pro_final_2026_2.git
```

El código de producto está directamente en `backend/`, `panel/` y `apps/*_mobile/`. Realiza los cambios de código y documentación en las carpetas correspondientes de este repositorio.

## Convenciones

- **Repositorio único**: las superficies de producto y la documentación se mantienen en este mismo repositorio.
- **Entornos**: todo se ejecuta con Docker Compose + Floci en local (endpoints/credenciales por configuración, nunca hardcodeados).
- **Commits**: conventional commits; una unidad de trabajo por commit.
