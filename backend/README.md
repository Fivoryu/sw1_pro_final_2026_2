# Backend (FastAPI)

API monolítica modular de RoomForge: identidad/autenticación, tenancy SaaS, publicaciones y catálogo.

- Stack: FastAPI · SQLAlchemy 2.x (psycopg) · Alembic · PostgreSQL · Argon2id · PyJWT · pytest
- Repositorio: [sw1_pro_final_backend_2026_2](https://github.com/Fivoryu/sw1_pro_final_backend_2026_2)
- Docs de arquitectura: [docs/scrum](../docs/scrum/sprint-0-requerimientos/09-infraestructura.md)
- Estado: identidad + autenticación (PB-001/PB-002) implementados y verificados; postgres local vía `infra/docker/compose.postgres.yml`
