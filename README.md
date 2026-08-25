# RoomForge — Monorepo

SaaS inmobiliario académico con recorridos 3D (ver [documentación del proyecto](docs/README.md)).

## Estructura

```text
proyecto_final/
├── docs/          # Documentación de Ingeniería de Software (PAPS, Scrum, Sprint 0–3)
├── apps/           # Aplicaciones móviles Flutter (Android 10+)
│   ├── cliente_mobile/  #   App del cliente: catálogo, recorridos, reservas
│   └── captura_mobile/  #   App de captura del agente (video + fotos + difuminado)
├── panel/         # Panel web React + TypeScript + Vite (admin/agente)
├── backend/       # API FastAPI monolítica modular (PostgreSQL, S3, SQS)
├── worker3d/      # Worker de reconstrucción 3D (Python + AliceVision/Meshroom)
├── contracts/     # Contratos Solidity/Hardhat (escrow de token de prueba)
├── infra/         # Docker Compose + Floci (dev), despliegue AWS (ECS Express)
├── scripts/       # Utilidades de automatización del equipo
└── skills/        # Skills de documentación (Pi)
```

## Convenciones
    
- **Repos individuales**: cada carpeta de producto tiene su repositorio propio (ver [Repositorios](#repositorios)); el monorepo conserva la documentación e integración del proyecto.
- **Entornos**: todo se ejecuta con Docker Compose + Floci en local (endpoints/credenciales por configuración, nunca hardcodeados).
- **Commits**: conventional commits; una unidad de trabajo por commit.
    
## Repositorios
    
| Producto | Carpeta | Repositorio |
| --- | --- | --- |
| Backend (FastAPI) | `backend/` | [sw1_pro_final_backend_2026_2](https://github.com/Fivoryu/sw1_pro_final_backend_2026_2) |
| Panel web (React/Vite) | `panel/` | [sw1_pro_final_frontend_2026_2](https://github.com/Fivoryu/sw1_pro_final_frontend_2026_2) |
| App captura (Flutter) | `apps/captura_mobile/` | [sw1_pro_final_captura_mobile_2026_2](https://github.com/Fivoryu/sw1_pro_final_captura_mobile_2026_2) |
| App cliente (Flutter) | `apps/cliente_mobile/` | [sw1_pro_final_cliente_mobile_2026_2](https://github.com/Fivoryu/sw1_pro_final_cliente_mobile_2026_2) |
