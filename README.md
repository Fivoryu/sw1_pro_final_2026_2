# RoomForge — Monorepo

SaaS inmobiliario académico con recorridos 3D (ver [documentación del proyecto](docs/README.md)).

## Repositorios

Seleccioná un repositorio para ver su código:

<div align="center">

<a href="https://github.com/Fivoryu/sw1_pro_final_backend_2026_2">
  <img src="https://img.shields.io/badge/Backend-FastAPI-059669?style=for-the-badge&logo=fastapi&logoColor=white"/>
</a>

<a href="https://github.com/Fivoryu/sw1_pro_final_frontend_2026_2">
  <img src="https://img.shields.io/badge/Panel%20Web-React-61DAFB?style=for-the-badge&logo=react&logoColor=black"/>
</a>

<a href="https://github.com/Fivoryu/sw1_pro_final_captura_mobile_2026_2">
  <img src="https://img.shields.io/badge/Captura-Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white"/>
</a>

<a href="https://github.com/Fivoryu/sw1_pro_final_cliente_mobile_2026_2">
  <img src="https://img.shields.io/badge/Cliente-Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white"/>
</a>

</div>

| Repositorio | Producto | Carpeta | Stack |
| --- | --- | --- | --- |
| [**sw1_pro_final_backend_2026_2**](https://github.com/Fivoryu/sw1_pro_final_backend_2026_2) 🔗 | API del servidor | `backend/` | FastAPI · PostgreSQL · Alembic · Argon2id |
| [**sw1_pro_final_frontend_2026_2**](https://github.com/Fivoryu/sw1_pro_final_frontend_2026_2) 🔗 | Panel web admin/agente | `panel/` | React · TypeScript · Vite |
| [**sw1_pro_final_captura_mobile_2026_2**](https://github.com/Fivoryu/sw1_pro_final_captura_mobile_2026_2) 🔗 | App captura del agente | `apps/captura_mobile/` | Flutter (Android 10+) |
| [**sw1_pro_final_cliente_mobile_2026_2**](https://github.com/Fivoryu/sw1_pro_final_cliente_mobile_2026_2) 🔗 | App del cliente | `apps/cliente_mobile/` | Flutter (Android 10+) |

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

- **Repos individuales**: cada carpeta de producto tiene su repositorio propio (ver [Repositorios](#repositorios) arriba); el monorepo conserva la documentación e integración del proyecto.
- **Entornos**: todo se ejecuta con Docker Compose + Floci en local (endpoints/credenciales por configuración, nunca hardcodeados).
- **Commits**: conventional commits; una unidad de trabajo por commit.
