# Sprint 0 — Infraestructura

| Campo | Valor |
| --- | --- |
| Módulo | S0-09 — CAPITULO 1, apartado 9 |
| Estado | planned (stack y hosting confirmados; números de planes pendientes) |
| IDs | INF; RNF-011/012/018; PB-047/048/049 |
| Fuentes | stack tecnológico (Engram obs-2276); hosting backend (obs-2405, decisión 2026-08-22); Docker+Floci (obs-2403); riesgos R4/R6 |

## Stack tecnológico

| Capa | Tecnología | Superficie |
| --- | --- | --- |
| Apps móviles | Flutter/Dart — Android 10+, 64-bit, 4 GB RAM (RNF-011); iOS solo compatibilidad de código (RNF-013) | App cliente, App captura |
| Panel web | React + TypeScript + Vite; visor Three.js en WebView | Panel admin/agente (Chrome/Edge, RNF-012) |
| Backend | FastAPI monolítico modular; autenticación Argon2id/JWT/refresh/RBAC | API |
| Base de datos | PostgreSQL (autoridad de estados y metadatos; JSONB opcional) | Datos transaccionales |
| Objetos | S3 (capturas, nubes PLY/LAZ, GLB, texturas, planos) | Binarios |
| Cola | Amazon SQS (jobs asíncronos con visibility timeout y reentrega) | Pipeline 3D |
| Reconstrucción | AliceVision/Meshroom + conversión a GLB; COLMAP como fallback | Worker 3D |
| Blockchain | Solidity + Hardhat + OpenZeppelin; escrow de token de prueba en red local | Escrow (ver `blockchain-enfoque.md`) |
| Emulación local | Docker Compose + Floci (S3/SQS) — mismo SDK, endpoints por configuración | Desarrollo/CI |
| Cloud | AWS: ECS Express Mode (Fargate) para la API; Amplify Hosting propuesto para el frontend; RDS; S3; SQS | Producción/demo |

## Entorno de desarrollo (SPK-05)

- Docker Compose: frontend, backend FastAPI, PostgreSQL, Floci (S3/SQS) y worker real o simulado.
- Credenciales y endpoints de Floci solo por configuración (`.env`), nunca hardcodeados.
- Checklist de 11 pasos por integrante en [`spk-05-smoke-test-local.md`](../../spikes/spk-05-smoke-test-local.md) (pendiente de ejecución).

## Hosting y despliegue

- **Backend**: ECS Express Mode (Fargate) — HTTPS/ALB/logs/autoescalado gestionados; decisión 2026-08-22.
- **Frontend**: Amplify Hosting (propuesto; react + vite, CDN y HTTPS).
- **Cuenta**: AWS personal; **no se despliega nada durante el desarrollo**; el despliegue ocurre días antes de la presentación (RNF-018).
- **Presupuesto**: sin números definitivos hasta confirmar cuenta/créditos/región (riesgo R4) y estimar con los spikes (GAP-061).
- **Worker 3D**: la PC RTX 4050 se conecta hacia afuera por HTTPS (polling a SQS), sin exposición pública; la GPU cloud queda solo como contingencia (riesgo R8).

## 5.1. Diagramas asociados

Tipos de diagrama según el modelo (ver [`tipos-diagramas-modelo.md`](../../sprint-0/tipos-diagramas-modelo.md)):

| Módulo | Tipo de diagrama |
| --- | --- |
| S0-07 — Casos de uso | **Use Case** |
| S0-08 — Planificación de Sprints (8.1) | **Gantt** |
| S0-11 — Modelos iniciales | **Contexto**, **Use Case**, **Class/ERD**, **Package/Component**, **Interfaces** |
| Sprint 1–3 — Diseño por HU (CAPITULO 2) | **Deployment**, **Package**, **ERD** (conceptual/lógico/físico), **Communication**, **Sequence**, **Component** + **Gráfica Burndown/BurnUp** y **Taskboard** |

## Pendientes de infraestructura

| Pendiente | GAP/Riesgo |
| --- | --- |
| Nombres, precios y cuotas de los 3 planes | GAP-061 (SPK-01/04) |
| Confirmar cuenta, créditos y región AWS | R4 (antes de la semana de despliegue) |
| Validación del entorno local por cada integrante | SPK-05 (not executed) |
| Confirmación explícita del hosting del frontend (Amplify) | GAP-091 (pendiente de decisión del equipo) |
