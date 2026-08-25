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
    
> ✅ **Modo multi-repo**: las carpetas de producto son **submódulos git** que apuntan a cada repositorio. Al navegar el monorepo, cada carpeta te redirige a su repo.
    
## Estructura
    
```text
proyecto_final/
├── docs/          # Documentación de Ingeniería de Software (PAPS, Scrum, Sprint 0–3)
├── apps/          # 🔗 submódulo → sw1_pro_final_captura_mobile_2026_2
│   ├── cliente_mobile/  #   App del cliente: catálogo, recorridos, reservas
│   └── captura_mobile/  #   App de captura del agente (video + fotos + difuminado)
├── panel/         # 🔗 submódulo → sw1_pro_final_frontend_2026_2
├── backend/       # 🔗 submódulo → sw1_pro_final_backend_2026_2
├── worker3d/      # Worker de reconstrucción 3D (Python + AliceVision/Meshroom)
├── contracts/     # Contratos Solidity/Hardhat (escrow de token de prueba)
├── infra/         # Docker Compose + Floci (dev), despliegue AWS (ECS Express)
├── scripts/       # Utilidades de automatización del equipo
└── skills/        # Skills de documentación (Pi)
```
    
## Clonado (multi-repo)
    
```bash
git clone --recurse-submodules https://github.com/Fivoryu/sw1_pro_final_2026_2.git
# o, si ya clonaste sin submódulos:
git submodule update --init --recursive
```
    
## Convenciones
    
- **Multi-repo**: `backend/`, `panel/` y `apps/*_mobile/` son submódulos de los 4 repositorios individuales; este monorepo conserva la documentación e integración del proyecto.
- **Entornos**: todo se ejecuta con Docker Compose + Floci en local (endpoints/credenciales por configuración, nunca hardcodeados).
- **Commits**: conventional commits; una unidad de trabajo por commit.
