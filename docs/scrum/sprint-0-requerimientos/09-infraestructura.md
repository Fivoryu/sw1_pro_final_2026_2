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
| Apps móviles | Flutter/Dart — Android 10+, 64-bit, 4 GB RAM (RNF-011); iOS solo compatibilidad de código (RNF-013) | App cliente, App captura con asistencia IA offline propuesta |
| IA de captura | Modelo externo/open-source por seleccionar y revisar; ajuste o entrenamiento local; exportación ONNX/TFLite; inferencia offline | App de captura (enfoque propuesto — pendiente de confirmación/formalización) |
| Panel web | React + TypeScript + Vite; visor Three.js en WebView | Panel admin/agente (Chrome/Edge, RNF-012) |
| Backend | FastAPI monolítico modular; autenticación Argon2id/JWT/refresh/RBAC | API |
| Base de datos | PostgreSQL (autoridad de estados y metadatos; JSONB opcional) | Datos transaccionales |
| Objetos | S3 (capturas, nubes PLY/LAZ, GLB, texturas, planos) | Binarios |
| Cola | Amazon SQS (jobs asíncronos con visibility timeout y reentrega) | Pipeline 3D |
| Reconstrucción | AliceVision/Meshroom + conversión a GLB; COLMAP como fallback; ejecución fuera del teléfono | Worker 3D local o PC/GPU prevista |
| Blockchain | Solidity + Hardhat + OpenZeppelin; escrow de token de prueba en red local, independiente de Floci | Escrow (ver `blockchain-enfoque.md`) |
| Emulación local | Docker Compose + Floci (solo S3/SQS) — mismo SDK, endpoints por configuración; no ejecuta Meshroom ni blockchain | Desarrollo/CI |
| Cloud | AWS: ECS Express Mode (Fargate) para la API; Amplify Hosting propuesto para el frontend; RDS; S3; SQS | Producción/demo |

## Entorno de desarrollo (SPK-05)

- Docker Compose: frontend, backend FastAPI, PostgreSQL, Floci (S3/SQS) y worker real o simulado.
- La app Flutter puede ejecutar la asistencia IA propuesta offline; la sincronización de capturas ocurre al recuperar conectividad.
- Credenciales y endpoints de Floci solo por configuración (`.env`), nunca hardcodeados.
- Checklist de 11 pasos por integrante en [`spk-05-smoke-test-local.md`](../../spikes/spk-05-smoke-test-local.md) (pendiente de ejecución).

## Capa de IA de captura

> **Enfoque propuesto — pendiente de confirmación/formalización:** se evaluará un modelo externo/open-source para asistir la captura. El ajuste o entrenamiento se realizará localmente en una PC propia y el modelo se exportará a ONNX o TFLite para empaquetarlo en la app Flutter.

- La inferencia de esta capa será offline y estará limitada a calidad, cobertura y señales de puertas, ventanas y superficies durante la captura.
- Esta capa no ejecutará Meshroom, no generará la reconstrucción 3D final y no reemplazará al worker3d.
- La selección del modelo, la revisión de su licencia, la compatibilidad con los dispositivos objetivo y sus métricas quedan pendientes de formalización.
- No se incorpora una API cloud paga como dependencia de inferencia o entrenamiento.

## Hosting y despliegue

- **Backend**: ECS Express Mode (Fargate) — HTTPS/ALB/logs/autoescalado gestionados; decisión 2026-08-22.
- **Frontend**: Amplify Hosting (propuesto; react + vite, CDN y HTTPS).
- **Cuenta**: AWS personal; **no se despliega nada durante el desarrollo**; el despliegue ocurre días antes de la presentación (RNF-018).
- **Presupuesto**: sin números definitivos hasta confirmar cuenta/créditos/región (riesgo R4) y estimar con los spikes (GAP-061).
- **Worker 3D**: la PC con GPU prevista se conecta hacia afuera por HTTPS (polling a SQS), sin exposición pública; la GPU cloud queda solo como contingencia (riesgo R8).

## Topología y conectividad

### Desarrollo local

```text
App Flutter de captura
  ├─ IA de asistencia offline
  └─ captura local ──(al reconectar)──> API FastAPI
                                      ├─ PostgreSQL
                                      ├─ Floci: S3/SQS
                                      └─ worker3d real o simulado
                                           └─ Meshroom en PC/GPU o proceso separado

Backend ──RPC──> Hardhat local (escrow de prueba, independiente de Floci)
```

- La app puede capturar y recibir asistencia sin conectividad; sincroniza al reconectar.
- Floci solo emula S3/SQS para desarrollo local. No ejecuta Meshroom ni la red Hardhat.
- El worker local puede ser real o simulado. Cuando es real, ejecuta Meshroom en una PC/GPU o en un proceso separado.
- Hardhat y contracts mantienen su propio flujo de token de prueba por RPC, con fallback de escrow simulado.

### Producción prevista

```text
App Flutter ──(cuando hay conectividad)──> API en AWS
                                          ├─ RDS
                                          ├─ S3/SQS
                                          └─ jobs asíncronos
                                               ↑ HTTPS saliente / polling
                                          PC con GPU: worker3d + Meshroom
```

- La app conserva la inferencia IA offline y sincroniza cuando puede conectarse a la API; no se presupone inferencia cloud.
- La PC con GPU inicia conexiones salientes por HTTPS para consultar SQS y leer/escribir objetos; no se expone públicamente.
- La producción prevista usa la PC con GPU para el worker3d. Una GPU cloud queda solo como contingencia, sin convertirla en dependencia del MVP.
- La topología conserva las responsabilidades: FastAPI orquesta, S3 almacena objetos, SQS transporta jobs y worker3d ejecuta Meshroom.

## Política de costes

- El objetivo monetario del desarrollo y del MVP es cero: hardware propio para ajuste o entrenamiento, inferencia offline, Floci local y Hardhat local.
- No se dependerá de una API cloud paga para la IA ni de una nube para ejecutar la reconstrucción durante el desarrollo.
- La licencia del modelo externo debe revisarse antes de adoptarlo; “open-source” no sustituye esa verificación.
- El despliegue AWS se mantiene diferido hasta días antes de la presentación conforme a RNF-018. No se agregan precios ni cuotas no confirmados.

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
